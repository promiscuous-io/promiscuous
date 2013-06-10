raise "mongoid > 3.0.19 please" unless Gem.loaded_specs['mongoid'].version >= Gem::Version.new('3.0.19')
raise "moped > 1.3.2 please"    unless Gem.loaded_specs['moped'].version   >= Gem::Version.new('1.3.2')

require 'yaml'

class Moped::PromiscuousCollectionWrapper < Moped::Collection
  class PromiscuousCollectionOperation < Promiscuous::Publisher::Operation::Base
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

    def serialize_document_for_create_recovery
      # TODO the serialization/deserialization is not very nice, but we need
      # the bson types.
      @document.to_yaml
    end

    def self.recover_operation(model, instance_id, document)
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

    def stash_version_in_write_query
      @document[VERSION_FIELD] = @instance_version
    end

    def execute_persistent(&db_operation)
      @instance = Mongoid::Factory.from_db(model, @document)
      super
    end

    def execute(&db_operation)
      return db_operation.call unless model
      super
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
  class PromiscuousQueryOperation < Promiscuous::Publisher::Operation::Base
    attr_accessor :raw_instance, :new_raw_instance, :change

    def initialize(options={})
      super
      @query = options[:query]
      @change = options[:change]
    end

    def collection_name
      @collection_name ||= @query.collection.is_a?(String) ? @query.collection : @query.collection.name
    end

    def model
      @model ||= Promiscuous::Publisher::Model::Mongoid.collection_mapping[collection_name]
    end

    def self.recover_operation(model, instance_id, document)
      # TODO We need to use the primary database. We cannot read from a
      # secondary.
      query = model.unscoped.where(:id => instance_id).query
      op = new(:query => query, :change => {})
      # TODO refactor this not so pretty instance_eval
      op.instance_eval do
        reload_instance
        @instance ||= get_selector_instance
      end
      op
    end

    def recover_db_operation
      # We no-op the update/destroy operation instead of making it idempotent.
      # The original caller will fail because the lock was unlocked.
      without_promiscuous { @query.update(@change) }
      @operation = :dummy
    end

    def fetch_instance
      @raw_instance = @new_raw_instance || without_promiscuous { @query.first }
      Mongoid::Factory.from_db(model, @raw_instance) if @raw_instance
    end

    def use_id_selector(options={})
      selector = {'_id' => @instance.id}

      if options[:use_atomic_version_selector]
        version = @instance[VERSION_FIELD]
        selector.merge!(VERSION_FIELD => version) if version
      end

      @query.selector = selector
    end

    def stash_version_in_write_query
      @change['$set'] ||= {}
      @change['$set'][VERSION_FIELD] = @instance_version
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

    def execute_persistent(&db_operation)
      # We are trying to be optimistic for the locking. We are trying to figure
      # out our dependencies with the selector upfront to avoid an extra read
      # from reload_instance.
      @instance = get_selector_instance
      super
    end

    def execute_non_persistent(&db_operation)
      if multi?
        @instance = get_selector_instance
        @selector_keys = @selector.keys
      end
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

    def execute(&db_operation)
      return db_operation.call if @query.without_promiscuous?
      return db_operation.call unless model
      return db_operation.call unless any_published_field_changed?

      # We cannot do multi update/destroy
      if (operation == :update || operation == :destroy) && multi?
        raise Promiscuous::Error::Dependency.new(:operation => self)
      end
      super
    end
  end

  def promiscuous_operation(operation, options={})
    PromiscuousQueryOperation.new(options.merge(:query => self, :operation => operation))
  end

  def selector=(value)
    @selector = value
    @operation.selector = value
  end

  def without_promiscuous!
    @without_promiscuous = true
  end

  def without_promiscuous?
    !!@without_promiscuous
  end

  # Moped::Query

  def count(*args)
    promiscuous_operation(:read, :multi => true, :operation_ext => :count).execute { super }.to_i
  end

  def distinct(key)
    promiscuous_operation(:read, :multi => true).execute { super }
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
    # TODO If the the user is using something like .only(), we need to make
    # sure that we add the id, otherwise we may not be able to perform the
    # dependency optimization by resolving the selector to an id.
    promiscuous_operation(:read).execute do |operation|
      operation ? operation.raw_instance : super
    end
  end
  alias :one :first

  def update(change, flags=nil)
    multi = flags && flags.include?(:multi)
    raise "No upsert support yet" if flags && flags.include?(:upsert)

    promiscuous_operation(:update, :change => change, :multi => multi).execute do |operation|
      if operation
        operation.new_raw_instance = without_promiscuous { modify(change, :new => true) }
        # FIXME raise when recovery raced
        {'updatedExisting' => true, 'n' => 1, 'err' => nil, 'ok' => 1.0}
      else
        super
      end
    end
  end

  def modify(change, options={})
    promiscuous_operation(:update, :change => change).execute { super }
    # FIXME raise when recovery raced
  end

  def remove
    promiscuous_operation(:destroy).execute { super }
    # FIXME raise when recovery raced
  end

  def remove_all
    promiscuous_operation(:destroy, :multi => true).execute { super }
  end
end

class Moped::PromiscuousCursorWrapper < Moped::Cursor
  def promiscuous_operation(op, options={})
    Moped::PromiscuousQueryWrapper::PromiscuousQueryOperation.new(
      options.merge(:query => @query, :operation => op))
  end

  # Moped::Cursor

  def fake_single_read(operation)
    @cursor_id = 0
    [operation.raw_instance].compact
  end

  def load_docs
    should_fake_single_read = @limit == 1
    promiscuous_operation(:read, :multi => !should_fake_single_read).execute do |operation|
      operation && should_fake_single_read ? fake_single_read(operation) : super
    end.to_a
  end

  def get_more
    # TODO support batch_size
    promiscuous_operation(:read, :multi => true).execute { super }
  end

  def initialize(session, query_operation)
    super
    @query = Thread.current[:moped_query]
  end
end

class Moped::PromiscuousDatabase < Moped::Database
  # TODO it might be safer to use the alias attribute method because promiscuous
  # may come late in the loading.
  def promiscuous_operation(op, options={})
    Moped::PromiscuousQueryWrapper::PromiscuousQueryOperation.new(
      options.merge(:operation => op))
  end

  # Moped::Database

  def command(command)
    if command[:mapreduce]
      query = Moped::Query.new(self[command[:mapreduce]], command[:query])
      promiscuous_operation(:read, :query => query,
                            :operation_ext => :mapreduce, :multi => true).execute { super }
    else
      super
    end
  end
end

class Mongoid::Contextual::Mongo
  alias_method :each_hijacked, :each

  def each(&block)
    query.without_promiscuous! if criteria.options[:without_promiscuous]
    each_hijacked(&block)
  end
end

module Origin::Optional
  def without_promiscuous
    clone.tap { |criteria| criteria.options.store(:without_promiscuous, true) }
  end
end

class Mongoid::Validations::UniquenessValidator
  alias_method :validate_root_without_promisucous, :validate_root
  def validate_root(*args)
    without_promiscuous { validate_root_without_promisucous(*args) }
  end
end

class Moped::BSON::ObjectId
  # No {"$oid": "123"}, it's horrible
  def to_json(*args)
    "\"#{to_s}\""
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
