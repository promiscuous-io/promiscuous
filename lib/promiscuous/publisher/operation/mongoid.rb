raise "mongoid > 3.0.19 please" unless Gem.loaded_specs['mongoid'].version >= Gem::Version.new('3.0.19')
raise "moped > 1.3.2 please"    unless Gem.loaded_specs['moped'].version   >= Gem::Version.new('1.3.2')

class Moped::PromiscuousCollectionWrapper < Moped::Collection
  class PromiscuousCollectionOperation < Promiscuous::Publisher::Operation::Base
    def initialize(options={})
      super
      @operation = :create
      @collection = options[:collection]
      @document   = options[:document]
    end

    def model
      return @model if @model
      @model = @document.try(:[], '_type').try(:constantize) ||
               Promiscuous::Publisher::Model::Mongoid.collection_mapping[@collection.name]
      @model = nil unless @model < Promiscuous::Publisher::Model::Mongoid
      @model
    rescue NameError
    end

    def _commit(transaction, &db_operation)
      @instance = Mongoid::Factory.from_db(model, @document)
      super
    end

    def commit(&db_operation)
      return db_operation.call unless model
      super
    rescue Promiscuous::Error::InactiveTransaction => e
      # Because we do lazy binding on @instance, the instance is still not
      # set at this point. It's useful to set it for error messages.
      @instance = Mongoid::Factory.from_db(model, @document)
      raise e
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
      promiscuous_create_operation(:document => doc).commit { super(doc, flags) }
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

    def model
      collection_name = @query.collection.is_a?(String) ? @query.collection : @query.collection.name
      @model ||= Promiscuous::Publisher::Model::Mongoid.collection_mapping[collection_name]
    end

    def fetch_instance
      @raw_instance = without_promiscuous { @query.first }
      Mongoid::Factory.from_db(model, @raw_instance) if @raw_instance
    end

    def use_id_selector
      @query.selector = @query.operation.selector = {'_id' => @instance.id}
    end

    def fetch_instance_after_update
      return Mongoid::Factory.from_db(model, @new_raw_instance) if @new_raw_instance
      super
    end

    def get_selector_instance
      selector = @query.operation.selector["$query"] || @query.operation.selector

      # TODO use the original instance for an update/delete, that would be
      # an even better hint.

      # We only support == selectors, no $in, or $gt.
      @selector = selector.select { |k,v| k =~ /^[^$]/ && !v.is_a?(Hash) }

      # @instance is not really a proper instance of a model, it's just a
      # convenient representation of a selector as explain in base.rb,
      # which explain why we don't want any constructor to be called.
      # Note that this optimistic mechanism also works with writes because
      # the instance gets reloaded once the lock is taken. If the
      # dependencies were incorrect, the locks will be released and
      # reacquired appropriately.
      model.allocate.tap { |doc| doc.instance_variable_set(:@attributes, @selector) }
    end

    def get_original_selector_instance
      selector = @query.operation.selector["$query"] || @query.operation.selector
      model.allocate.tap { |doc| doc.instance_variable_set(:@attributes, selector) }
    end

    def _commit(transaction, &db_operation)
      # We need to operate on the primary from now on, because we need to make
      # sure that the reads we are doing on the database match their dependencies.
      @query.strong_consistency!

      begin
        # We are trying to be optimistic for the locking. We are trying to figure
        # out our dependencies with the selector upfront to avoid an extra read.
        @instance = get_selector_instance
        super
      rescue Promiscuous::Error::Dependency => e
        # Note that only read operations can throw such exceptions.
        if multi?
          # When doing the multi read, we cannot resolve the selector to a
          # specific id, (or we would have to do the count ourselves, which is
          # not desirable).
          @instance = get_original_selector_instance
          e.dependency_solutions = @selector.keys
          raise e
        else
          # in the case of a single read, we can resolve the selector to an id
          # one, which means that we have to pay an extra read.
          return nil unless reload_instance
          super
        end
      end
    end

    def fields_in_query(change)
      # We are going to extract all the keys in any nested hashes, this will be the
      # list of fields that can potentially change during the update.
      if change.is_a?(Hash)
        fields = change.keys + change.values.map(&method(:fields_in_query)).flatten
        # The split on . is for embedded documents, we don't look further down.
        fields.map { |f| f.to_s.split('.').first}.select { |k| k =~ /^[^$]/ }.uniq
      else
        []
      end
    end

    def any_published_field_changed?
      return true unless @change

      # TODO maybe we should cache these things
      # TODO discover field dependencies automatically (hard)
      aliases = Hash[model.aliased_fields.map { |k,v| [v,k] }]
      attributes = fields_in_query(@change).map { |f| (aliases[f.to_s] || f).to_sym }
      (attributes & model.published_db_fields).present?
    end

    def commit(&db_operation)
      return db_operation.call unless model
      return db_operation.call unless any_published_field_changed?

      # We cannot do multi update/destroy
      if (operation == :update || operation == :destroy) && multi?
        raise Promiscuous::Error::Dependency.new(:operation => self)
      end
      super
    rescue Promiscuous::Error::InactiveTransaction => e
      # Because we do lazy binding on @instance, the instance is still not
      # set at this point. It's useful to set it for error messages.
      @instance = get_selector_instance
      raise e
    end
  end

  def promiscuous_operation(operation, options={})
    PromiscuousQueryOperation.new(options.merge(:query => self, :operation => operation))
  end

  def selector=(value)
    @selector = value
  end

  def session
    @session || super
  end

  def strong_consistency!
    @session = session.with(:consistency => :strong)
  end

  # Moped::Query

  def count(*args)
    promiscuous_operation(:read, :multi => true, :operation_ext => :count).commit { super }.to_i
  end

  def distinct(key)
    promiscuous_operation(:read, :multi => true).commit { super }
  end

  def each
    old_moped_query, Thread.current[:moped_query] = Thread.current[:moped_query], self
    super
  ensure
    Thread.current[:moped_query] = old_moped_query
  end

  def first
    # TODO If the the user is using something like .only(), we need to make
    # sure that we add the id, otherwise we may not be able to perform the
    # dependency optimization by resolving the selector to an id.
    promiscuous_operation(:read).commit do |operation|
      operation ? operation.raw_instance : super
    end
  end

  def update(change, flags=nil)
    multi = flags && flags.include?(:multi)
    promiscuous_operation(:update, :change => change, :multi => multi).commit do |operation|
      if operation
        operation.new_raw_instance = without_promiscuous { modify(change, :new => true) }
        {'updatedExisting' => true, 'n' => 1, 'err' => nil, 'ok' => 1.0}
      else
        super
      end
    end
  end

  def modify(change, options={})
    promiscuous_operation(:update, :change => change).commit { super }
  end

  def remove
    promiscuous_operation(:destroy).commit { super }
  end

  def remove_all
    promiscuous_operation(:destroy, :multi => true).commit { super }
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
    promiscuous_operation(:read, :multi => !should_fake_single_read).commit do |operation|
      result = operation && should_fake_single_read ? fake_single_read(operation) : super
      operation.missed = true if operation && result.blank?
      result
    end.to_a
  end

  def get_more
    # TODO support batch_size
    promiscuous_operation(:read, :multi => true).commit { super }
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
                            :operation_ext => :mapreduce, :multi => true).commit { super }
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
