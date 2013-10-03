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

    def stash_version_in_write_query(version)
      @document[Promiscuous::Config.version_field] = version
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
  class PromiscuousQueryOperation < Promiscuous::Publisher::Operation::Atomic
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

    def recovery_payload
      [@instance.class.promiscuous_collection_name, @instance.id]
    end

    def self.recover_operation(collection, instance_id)
      # TODO We need to use the primary database. We cannot read from a secondary.
      model = Promiscuous::Publisher::Model::Mongoid.collection_mapping[collection]
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
      selector = {'_id' => @instance.id}.merge(@query.selector.select { |k,v| k.to_s.include?("_id") })

      if options[:use_atomic_version_selector]
        version = @instance[Promiscuous::Config.version_field]
        selector.merge!(Promiscuous::Config.version_field => version)
      end

      @query.selector = selector
    end

    def stash_version_in_write_query(version)
      @change['$set'] ||= {}
      @change['$set'][Promiscuous::Config.version_field] = version
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
      super
      @instance ||= get_selector_instance
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
      return db_operation.call unless model
      return db_operation.call unless any_published_field_changed?

      super
    end

    def nop?
      @instance.nil?
    end
  end

  def promiscuous_operation(operation, options={})
    PromiscuousQueryOperation.new(options.merge(:query => self, :operation => operation))
  end

  def selector=(value)
    @selector = value
    @operation.selector = value
  end

  # Moped::Query

  def count(*args)
    promiscuous_operation(:read, :operation_ext => :count).execute { super }.to_i
  end

  def distinct(key)
    promiscuous_operation(:read, :operation_ext => :distinct).execute { super }
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
    promiscuous_operation(:read).execute { super }
  end
  alias :one :first

  def update(change, flags=nil)
    if flags
      raise "You cannot do a multi update. Instead, update each document separately." if flags.include?(:multi)
      raise "No upsert support yet" if flags.include?(:upsert)
    end

    promiscuous_operation(:update, :change => change).execute do |operation|
      if operation
        operation.new_raw_instance = without_promiscuous { modify(change, :new => true) }
        {'updatedExisting' => true, 'n' => 1, 'err' => nil, 'ok' => 1.0}
      else
        super
      end
    end
  end

  def modify(change, options={})
    promiscuous_operation(:update, :change => change).execute { super }
  end

  def remove
    promiscuous_operation(:destroy).execute { super }
  end

  def remove_all
    raise "Instead of doing a multi delete, delete each document separatly.\n" +
          "Declare your has_many relationships with :dependent => :destroy instead of :delete"
  end
end

class Moped::PromiscuousCursorWrapper < Moped::Cursor
  def promiscuous_operation(op, options={})
    Moped::PromiscuousQueryWrapper::PromiscuousQueryOperation.new(
      options.merge(:query => @query, :operation => op, :operation_ext => :each))
  end

  # Moped::Cursor

  def load_docs
    promiscuous_operation(:read).execute { super }.to_a
  end

  def get_more
    # TODO support batch_size
    promiscuous_operation(:read).execute { super }
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
                            :operation_ext => :mapreduce).execute { super }
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

class Moped::BSON::ObjectId
  # No {"$oid": "123"}, it's horrible.
  # TODO Document this shit.
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
