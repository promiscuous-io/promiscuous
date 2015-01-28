class ActiveRecord::Base
  class << self
    alias_method :connection_without_promiscuous, :connection

    def connection
      connection_without_promiscuous.tap do |connection|
        unless defined?(connection.promiscuous_hook)
          connection.class.class_eval do
            attr_accessor :current_transaction_id

            def promiscuous_hook; end

            alias_method :begin_db_transaction_without_promiscuous,    :begin_db_transaction
            alias_method :create_savepoint_without_promiscuous,        :create_savepoint
            alias_method :rollback_db_transaction_without_promiscuous, :rollback_db_transaction
            alias_method :rollback_to_savepoint_without_promiscuous,   :rollback_to_savepoint
            alias_method :commit_db_transaction_without_promiscuous,   :commit_db_transaction
            alias_method :release_savepoint_without_promiscuous,       :release_savepoint

            def with_promiscuous_transaction_context(&block)
              block.call(Promiscuous::Publisher::Context.current.transaction_context_of(:active_record))
            end

            def begin_db_transaction
              @current_transaction_id = SecureRandom.uuid
              begin_db_transaction_without_promiscuous
              with_promiscuous_transaction_context { |tx| tx.start }
            end

            def create_savepoint
              create_savepoint_without_promiscuous
              with_promiscuous_transaction_context { |tx| tx.start }
            end

            def rollback_db_transaction
              with_promiscuous_transaction_context { |tx| tx.rollback }
              rollback_db_transaction_without_promiscuous
              @current_transaction_id = nil
            end

            def rollback_to_savepoint
              with_promiscuous_transaction_context { |tx| tx.rollback }
              rollback_to_savepoint_without_promiscuous
            end

            def commit_db_transaction
              ops = with_promiscuous_transaction_context { |tx| tx.write_operations_to_commit }
              PromiscuousTransaction.new(:connection => self,
                                         :transaction_id => self.current_transaction_id,
                                         :transaction_operations => ops).execute do
                commit_db_transaction_without_promiscuous
              end
              with_promiscuous_transaction_context { |tx| tx.commit }
              @current_transaction_id = nil
            end

            def release_savepoint
              release_savepoint_without_promiscuous
              with_promiscuous_transaction_context { |tx| tx.commit }
            end

            def supports_returning_statments?
              @supports_returning_statments ||= ["ActiveRecord::ConnectionAdapters::PostgreSQLAdapter",
                                                 "ActiveRecord::ConnectionAdapters::OracleEnhancedAdapter"].include?(self.class.name)
            end

            alias_method :insert_without_promiscuous, :insert
            alias_method :update_without_promiscuous, :update
            alias_method :delete_without_promiscuous, :delete

            def insert(arel, name = nil, pk = nil, id_value = nil, sequence_name = nil, binds = [])
              PromiscuousInsertOperation.new(arel, name, pk, id_value, sequence_name, binds, :connection => self).execute do
                insert_without_promiscuous(arel, name, pk, id_value, sequence_name, binds)
              end
            end

            def update(arel, name = nil, binds = [])
              PromiscuousUpdateOperation.new(arel, name, binds, :connection => self).execute do
                update_without_promiscuous(arel, name, binds)
              end
            end

            def delete(arel, name = nil, binds = [])
              PromiscuousDeleteOperation.new(arel, name, binds, :connection => self).execute do
                delete_without_promiscuous(arel, name, binds)
              end
            end
          end
        end
      end
    end
  end

  class PromiscousOperation < Promiscuous::Publisher::Operation::NonPersistent
    def initialize(arel, name, binds, options={})
      super(options)
      @arel = arel
      @name = name
      @binds = binds
      @connection = options[:connection]
    end

    def transaction_context
      Promiscuous::Publisher::Context.current.transaction_context_of(:active_record)
    end

    def ensure_transaction!
      if !transaction_context.in_transaction?
        raise "You need to write to the database within an ActiveRecord transaction"
      end
    end

    def model
      @model ||= @arel.ast.relation.engine
      @model = nil unless @model < Promiscuous::Publisher::Model::ActiveRecord
      @model
    end

    def execute(&db_operation)
      return db_operation.call unless model
      ensure_transaction!

      super do |query|
        query.non_instrumented { db_operation.call }
        query.instrumented do
          db_operation_and_select.tap do
            @operations.each { |operation| transaction_context.add_write_operation(operation) }
          end
        end
      end
    end

    def db_operation_and_select
      raise
    end
  end

  class PromiscuousInsertOperation < PromiscousOperation
    def initialize(arel, name, pk, id_value, sequence_name, binds, options={})
      super(arel, name, binds, options)
      @pk = pk
      @id_value = id_value
      @sequence_name = sequence_name
      @operation_name = :create
      raise unless @arel.is_a?(Arel::InsertManager)
    end

    def db_operation_and_select
      # XXX This is only supported by Postgres and should be in the postgres driver
      @connection.transaction do
        if @connection.supports_returning_statments?
          @connection.exec_insert("#{@connection.to_sql(@arel, @binds)} RETURNING *", @name, @binds).tap do |result|
            @operations = result.map do |row|
              Promiscuous::Publisher::Operation::NonPersistent.new(:instance => model.instantiate(row), :operation_name => @operation_name)
            end
          end
        else
          @connection.exec_insert("#{@connection.to_sql(@arel, @binds)}", @name, @binds)

          id = @binds.select { |k,v| k.name == 'id' }.first.last rescue nil
          id ||= @connection.instance_eval { @connection.last_id }
          id.tap do |last_id|
            result = @connection.exec_query("SELECT * FROM #{model.table_name} WHERE #{@pk} = #{last_id}")
            @operations = result.map do |row|
              Promiscuous::Publisher::Operation::NonPersistent.new(:instance => model.instantiate(row), :operation_name => @operation_name)
            end
          end
        end
      end
      # TODO Use correct primary key
      @operations.first.instance.id
    end
  end

  class PromiscuousUpdateOperation < PromiscousOperation
    def initialize(arel, name, binds, options={})
      super
      @operation_name = :update
      return if Promiscuous.disabled?
      raise unless @arel.is_a?(Arel::UpdateManager)
    end

    def updated_fields_in_query
      Hash[@arel.ast.values.map do |v|
        case v
        when Arel::Nodes::Assignment
          [v.left.name.to_sym, v.right]
        when Arel::Nodes::SqlLiteral
          # Not parsing SQL, no thanks. It's an optimization anyway
          return nil
        else
          return nil
        end
      end]
    end

    def any_published_field_changed?
      updates = updated_fields_in_query
      return true if updates.nil? # Couldn't parse query
      (updated_fields_in_query.keys & model.published_db_fields).present?
    end

    def sql_select_statment
      arel = @arel.dup
      arel.instance_eval { @ast = @ast.dup }
      arel.ast.values = []
      @connection.to_sql(arel, [@binds.last]).sub(/^UPDATE /, 'SELECT * FROM ')
    end

    def db_operation_and_select
      # TODO this should be in the postgres driver (to also leverage the cache)
      @arel.ast.values << Arel::Nodes::SqlLiteral.new("#{Promiscuous::Config.version_field} = COALESCE(#{Promiscuous::Config.version_field}, 0) + 1")

      if @connection.supports_returning_statments?
        @connection.exec_query("#{@connection.to_sql(@arel, @binds)} RETURNING *", @name, @binds).tap do |result|
          @operations = result.map do |row|
            Promiscuous::Publisher::Operation::NonPersistent.new(:instance => model.instantiate(row), :operation_name => @operation_name)
          end
        end.rows.size
      else
        @connection.exec_update(@connection.to_sql(@arel, @binds), @name, @binds).tap do
          result = @connection.exec_query(sql_select_statment, @name)
          @operations = result.map do |row|
            Promiscuous::Publisher::Operation::NonPersistent.new(:instance => model.instantiate(row), :operation_name => @operation_name)
          end
        end
      end
    end

    def execute(&db_operation)
      return db_operation.call if Promiscuous.disabled?
      return db_operation.call unless model
      return db_operation.call unless any_published_field_changed?
      super
    end
  end

  class PromiscuousDeleteOperation < PromiscousOperation
    def initialize(arel, name, binds, options={})
      super
      @operation_name = :destroy
      raise unless @arel.is_a?(Arel::DeleteManager)
    end

    def sql_select_statment
      @connection.to_sql(@arel.dup, @binds.dup).sub(/^DELETE /, 'SELECT * ')
    end

    def db_operation_and_select
      if @connection.supports_returning_statments?
        @connection.exec_query("#{@connection.to_sql(@arel, @binds)} RETURNING *", @name, @binds).tap do |result|
          @operations = result.map do |row|
            Promiscuous::Publisher::Operation::NonPersistent.new(:instance => model.instantiate(row), :operation_name => @operation_name)
          end
        end.rows.size
      else
        result = @connection.exec_query(sql_select_statment, @name, @binds)
          @operations = result.map do |row|
            Promiscuous::Publisher::Operation::NonPersistent.new(:instance => model.instantiate(row), :operation_name => @operation_name)
          end
        @connection.exec_delete(@connection.to_sql(@arel, @binds), @name, @binds)
      end
    end
  end

  class PromiscuousTransaction < Promiscuous::Publisher::Operation::Transaction
    attr_accessor :connection

    def initialize(options={})
      super
      # When we do a recovery, we use the default connection.
      @connection = options[:connection] || ActiveRecord::Base.connection
    end

    def execute_instrumented(query)
      query.instrumented { @connection.commit_db_transaction_without_promiscuous }
      super
    end
  end
end
