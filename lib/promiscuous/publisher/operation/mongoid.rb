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

    def execute_instrumented(query)
      @instance = Mongoid::Factory.from_db(model, @document)
      super
    end

    def should_instrument_query?
      super && model
    end

    def increment_version_in_document
      @document[Promiscuous::Config.version_field.to_s] = 1
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

    def execute_instrumented(query)
      @instance = get_selector_instance
      super
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

    def fetch_instance
      raw_instance = without_promiscuous { @query.first }
      @instance = Mongoid::Factory.from_db(model, raw_instance) if raw_instance
    end

    def increment_version_in_document
      @change['$inc'] ||= {}
      @change['$inc'][Promiscuous::Config.version_field.to_s] = 1
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
      aliases = Hash[model.aliased_fields.map { |k,v| [v,k] }]
      attributes = fields_in_query(@change).map { |f| [aliases[f.to_s], f] }.flatten.compact.map(&:to_sym)
      (attributes & model.published_db_fields).present?
    end

    def should_instrument_query?
      super && model && any_published_field_changed?
    end
  end

  # XXX Should not be needed
  class PromiscuousReadOperation < Promiscuous::Publisher::Operation::NonPersistent
    include Moped::PromiscuousQueryWrapper::PromiscuousHelpers

    def initialize(options={})
      super
      @operation = :read
      @query = options[:query]
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

  def update(change, flags=nil)
    update_op = promiscuous_write_operation(:update, :change => change)

    if flags && update_op.should_instrument_query?
      raise "You cannot do a multi update. Instead, update each document separately." if flags.include?(:multi)
      raise "No upsert support yet" if flags.include?(:upsert) # TODO Should be possible with new architecture
    end

    update_op.execute do |query|
      query.non_instrumented { super }
      query.instrumented do |op|
        if raw_instance = without_promiscuous { modify(change, :new => true) }
          op.instance = Mongoid::Factory.from_db(op.model, raw_instance)
        else
          op.instance = nil
        end
        {'updatedExisting' => true, 'n' => 1, 'err' => nil, 'ok' => 1.0}
      end
    end
  end

  def modify(change, options={})
    promiscuous_write_operation(:update, :change => change).execute do |query|
      query.non_instrumented { super }
      query.instrumented do |op|
        raise "You can only use find_and_modify() with :new => true" if !options[:new]
        super.tap do |raw_instance|
          if raw_instance
            op.instance = Mongoid::Factory.from_db(op.model, raw_instance) 
          else
            op.instance = nil
          end
        end
      end
    end
  end

  def remove
    promiscuous_write_operation(:destroy).execute { super }
  end

  def remove_all
    raise "Promiscuous: Instead of doing a multi delete, delete each document separatly.\n" +
          "Declare your has_many relationships with :dependent => :destroy instead of :delete"
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

Moped.__send__(:remove_const, :Collection)
Moped.__send__(:const_set,    :Collection, Moped::PromiscuousCollectionWrapper)
Moped.__send__(:remove_const, :Query)
Moped.__send__(:const_set,    :Query, Moped::PromiscuousQueryWrapper)
Moped.__send__(:remove_const, :Database)
Moped.__send__(:const_set,    :Database, Moped::PromiscuousDatabase)
