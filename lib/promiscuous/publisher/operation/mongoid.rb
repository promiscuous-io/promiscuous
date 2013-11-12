raise "mongoid > 3.0.19 please" unless Gem.loaded_specs['mongoid'].version >= Gem::Version.new('3.0.19')
raise "moped > 1.3.2 please"    unless Gem.loaded_specs['moped'].version   >= Gem::Version.new('1.3.2')

require 'yaml'

class Moped::PromiscuousCollectionWrapper < Moped::Collection
  class PromiscuousCollectionOperation < Promiscuous::Publisher::Operation::Atomic
    def initialize(options={})
      super
      @operation = :create
      @collection = options[:collection]
      @document   = options[:document]
    end

    def model
      @model ||= @document.try(:[], '_type').try(:constantize) ||
                 Promiscuous::Publisher::Model::Mongoid.collection_mapping[@collection.name]
      # Double check because of the _type lookup
      @model = nil unless @model < Promiscuous::Publisher::Model::Mongoid
      @model
    rescue NameError
    end

    def recovery_payload
      # We use yaml because we need the BSON types.
      [@instance.class.promiscuous_collection_name, @instance.id, @document.to_yaml]
    end

    def self.recover_operation(collection, instance_id, document)
      model = Promiscuous::Publisher::Model::Mongoid.collection_mapping[collection]
      document = YAML.load(document)
      instance = Mongoid::Factory.from_db(model, document)
      new(:collection => model.collection, :document => document, :instance => instance)
    end

    def recover_db_operation
      without_promiscuous do
        return if model.unscoped.where(:id => @instance.id).first # already done?
        @collection.insert(@document)
      end
    end

    def execute_instrumented(query)
      @instance = Mongoid::Factory.from_db(model, @document)
      super
    end

    def should_instrument_query?
      super && model
    end

    def recoverable_failure?(exception)
      exception.is_a?(Moped::Errors::ConnectionFailure)
    end
  end

  def promiscuous_create_operation(options)
    PromiscuousCollectionOperation.new(options.merge(:collection => self, :operation => :create))
  end

  # Moped::Collection

  # Create has its own Operation class, as it's the only scenario where there
  # is no matching document in the database
  def insert(documents, flags=nil)
    documents = [documents] unless documents.is_a?(Array)
    documents.each do |doc|
      promiscuous_create_operation(:document => doc).execute { super(doc, flags) }
    end
  end

  # TODO aggregate
end

class Moped::PromiscuousQueryWrapper < Moped::Query
  module PromiscuousHelpers
    def collection_name
      @collection_name ||= @query.collection.is_a?(String) ? @query.collection : @query.collection.name
    end

    def model
      @model ||= Promiscuous::Publisher::Model::Mongoid.collection_mapping[collection_name]
    end

    def get_selector_instance
      selector = @query.operation.selector["$query"] || @query.operation.selector

      # TODO use the original instance for an update/delete, that would be
      # an even better hint.

      # We only support == selectors, no $in, or $gt.
      @selector = selector.select { |k,v| k.to_s =~ /^[^$]/ && !v.is_a?(Hash) }

      # @instance is not really a proper instance of a model, it's just a
      # convenient representation of a selector as explain in base.rb,
      # which explain why we don't want any constructor to be called.
      # Note that this optimistic mechanism also works with writes because
      # the instance gets reloaded once the lock is taken. If the
      # dependencies were incorrect, the locks will be released and
      # reacquired appropriately.
      model.allocate.tap { |doc| doc.instance_variable_set(:@attributes, @selector) }
    end
  end

  class PromiscuousWriteOperation < Promiscuous::Publisher::Operation::Atomic
    include Moped::PromiscuousQueryWrapper::PromiscuousHelpers

    attr_accessor :change

    def initialize(options={})
      super
      @query = options[:query]
      @change = options[:change]
    end

    def recovery_payload
      [@instance.class.promiscuous_collection_name, @instance.id]
    end

    def self.recover_operation(collection, instance_id)
      # TODO We need to use the primary database. We cannot read from a secondary.
      model = Promiscuous::Publisher::Model::Mongoid.collection_mapping[collection]
      query = model.unscoped.where(:id => instance_id).query

      # We no-op the update operation instead of making it idempotent.
      # To do so, we do a dummy update on the document.
      # The original caller will fail because the lock was unlocked, so we'll
      # won't send a different message.
      new(:query => query, :change => {}).tap { |op| op.instance_eval { reload_instance } }
    end

    def recover_db_operation
      if operation == :update
        without_promiscuous { @query.update(@change) }
      else
        without_promiscuous { @query.remove }
      end
    end

    def recoverable_failure?(exception)
      exception.is_a?(Moped::Errors::ConnectionFailure)
    end

    def fetch_instance
      raw_instance = without_promiscuous { @query.first }
      Mongoid::Factory.from_db(model, raw_instance) if raw_instance
    end

    def use_id_selector(options={})
      selector = {'_id' => @instance.id}.merge(@query.selector.select { |k,v| k.to_s.include?("_id") })

      if options[:use_atomic_version_selector]
        version = @instance[Promiscuous::Config.version_field]
        selector.merge!(Promiscuous::Config.version_field => version)
      end

      @query.selector = selector
    end

    def stash_version_in_document(version)
      @change['$set'] ||= {}
      @change['$set'][Promiscuous::Config.version_field] = version
    end

    def execute_instrumented(query)
      # We are trying to be optimistic for the locking. We are trying to figure
      # out our dependencies with the selector upfront to avoid an extra read
      # from reload_instance.
      @instance ||= get_selector_instance
      super
    end

    def fields_in_query(change)
      # We are going to extract all the keys in any nested hashes, this will be the
      # list of fields that can potentially change during the update.
      if change.is_a?(Hash)
        fields = change.keys + change.values.map(&method(:fields_in_query)).flatten
        # The split on . is for embedded documents, we don't look further down.
        fields.map { |f| f.to_s.split('.').first}.select { |k| k.to_s =~ /^[^$]/ }.uniq
      else
        []
      end
    end

    def any_published_field_changed?
      return true unless @change

      # TODO maybe we should cache these things
      # TODO discover field dependencies automatically (hard)
      aliases = Hash[model.aliased_fields.map { |k,v| [v,k] }]
      attributes = fields_in_query(@change).map { |f| [aliases[f.to_s], f] }.flatten.compact.map(&:to_sym)
      (attributes & model.published_db_fields).present?
    end

    def should_instrument_query?
      super && model && any_published_field_changed?
    end
  end

  class PromiscuousReadOperation < Promiscuous::Publisher::Operation::NonPersistent
    include Moped::PromiscuousQueryWrapper::PromiscuousHelpers

    def initialize(options={})
      super
      @operation = :read
      @query = options[:query]
    end

    def query_dependencies
      deps = dependencies_for(get_selector_instance)
      deps.empty? ? super : deps
    end

    def should_instrument_query?
      super && model
    end
  end

  def promiscuous_read_operation(options={})
    PromiscuousReadOperation.new(options.merge(:query => self))
  end

  def promiscuous_write_operation(operation, options={})
    PromiscuousWriteOperation.new(options.merge(:query => self, :operation => operation))
  end

  def selector=(value)
    @selector = value
    @operation.selector = value
  end

  # Moped::Query

  def count(*args)
    promiscuous_read_operation(:operation_ext => :count).execute { super }.to_i
  end

  def distinct(key)
    promiscuous_read_operation(:operation_ext => :distinct).execute { super }
  end

  def each
    # The TLS is used to pass arguments to the Cursor so we don't hijack more than
    # necessary.
    old_moped_query, Thread.current[:moped_query] = Thread.current[:moped_query], self
    super
  ensure
    Thread.current[:moped_query] = old_moped_query
  end
  alias :cursor :each

  def first
    # FIXME If the the user is using something like .only(), we need to make
    # sure that we add the id, otherwise we are screwed.
    op = promiscuous_read_operation

    op.execute do |query|
      query.non_instrumented { super }
      query.instrumented do
        super.tap do |doc|
          op.instances = doc ? [Mongoid::Factory.from_db(op.model, doc)] : []
        end
      end
    end
  end
  alias :one :first

  def update(change, flags=nil)
    update_op = promiscuous_write_operation(:update, :change => change)

    if flags && update_op.should_instrument_query?
      raise "You cannot do a multi update. Instead, update each document separately." if flags.include?(:multi)
      raise "No upsert support yet" if flags.include?(:upsert)
    end

    update_op.execute do |query|
      query.non_instrumented { super }
      query.instrumented do |op|
        raw_instance = without_promiscuous { modify(change, :new => true) }
        op.instance = Mongoid::Factory.from_db(op.model, raw_instance)
        {'updatedExisting' => true, 'n' => 1, 'err' => nil, 'ok' => 1.0}
      end
    end
  end

  def modify(change, options={})
    promiscuous_write_operation(:update, :change => change).execute do |query|
      query.non_instrumented { super }
      query.instrumented do |op|
        raise "You can only use find_and_modify() with :new => true" if !options[:new]
        super.tap { |raw_instance| op.instance = Mongoid::Factory.from_db(op.model, raw_instance) }
      end
    end
  end

  def remove
    promiscuous_write_operation(:destroy).execute { super }
  end

  def remove_all
    raise "Instead of doing a multi delete, delete each document separatly.\n" +
          "Declare your has_many relationships with :dependent => :destroy instead of :delete"
  end
end

class Moped::PromiscuousCursorWrapper < Moped::Cursor
  # Moped::Cursor
  def promiscuous_read_each(&block)
    op = Moped::PromiscuousQueryWrapper::PromiscuousReadOperation.new(
           :query => @query, :operation_ext => :each)

    op.execute do |query|
      query.non_instrumented { block.call.to_a }
      query.instrumented do
        block.call.to_a.tap do |docs|
          op.instances = docs.map { |doc| Mongoid::Factory.from_db(op.model, doc) }
        end
      end
    end
  end

  def load_docs
    promiscuous_read_each { super }
  end

  def get_more
    # TODO support batch_size
    promiscuous_read_each { super }
  end

  def initialize(session, query_operation)
    super
    @query = Thread.current[:moped_query]
  end
end

class Moped::PromiscuousDatabase < Moped::Database
  # TODO it might be safer to use the alias attribute method because promiscuous
  # may come late in the loading.
  def promiscuous_read_operation(options={})
    Moped::PromiscuousQueryWrapper::PromiscuousReadOperation.new(options)
  end

  # Moped::Database

  def command(command)
    if command[:mapreduce]
      query = Moped::Query.new(self[command[:mapreduce]], command[:query])
      promiscuous_read_operation(:query => query, :operation_ext => :mapreduce).execute { super }
    else
      super
    end
  end
end

class Mongoid::Validations::UniquenessValidator
  alias_method :validate_root_without_promisucous, :validate_root
  def validate_root(*args)
    without_promiscuous { validate_root_without_promisucous(*args) }
  end
end

Moped.__send__(:remove_const, :Collection)
Moped.__send__(:const_set,    :Collection, Moped::PromiscuousCollectionWrapper)
Moped.__send__(:remove_const, :Query)
Moped.__send__(:const_set,    :Query, Moped::PromiscuousQueryWrapper)
Moped.__send__(:remove_const, :Cursor)
Moped.__send__(:const_set,    :Cursor, Moped::PromiscuousCursorWrapper)
Moped.__send__(:remove_const, :Database)
Moped.__send__(:const_set,    :Database, Moped::PromiscuousDatabase)
