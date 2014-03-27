class ActiveRecord::Base
  module PostgresSQL2PCExtensions
    extend ActiveSupport::Concern

    def prepare_db_transaction
      execute("PREPARE TRANSACTION '#{quote_string(@current_transaction_id)}'")
    end

    def commit_prepared_db_transaction(xid)
      # We might always be racing with another instance, these sort of errors
      # are spurious.
      execute("COMMIT PREPARED '#{quote_string(xid)}'")
    rescue Exception => e
      raise unless e.message =~ /^PG::UndefinedObject/
    end

    def rollback_prepared_db_transaction(xid, options={})
      execute("ROLLBACK PREPARED '#{quote_string(xid)}'")
    rescue Exception => e
      raise unless e.message =~ /^PG::UndefinedObject/
    end

    included do
      # We want to make sure that we never block the database by having
      # uncommitted transactions.
      Promiscuous::Publisher::Operation::Base.register_recovery_mechanism do
        connection = ActiveRecord::Base.connection
        db_name = connection.current_database

        # We wait twice the time of expiration, to allow a better recovery scenario.
        expire_duration = 2 * Promiscuous::Publisher::Operation::Base.lock_options[:expire]

        q = "SELECT gid FROM pg_prepared_xacts " +
            "WHERE database = '#{db_name}' " +
            "AND prepared < current_timestamp + #{expire_duration} * interval '1 second'"

        connection.exec_query(q, "Promiscuous Recovery").each do |tx|
          ActiveRecord::Base::PromiscuousTransaction.recover_transaction(connection, tx['gid'])
        end
      end
    end
  end

  class << self
    alias_method :connection_without_promiscuous, :connection

    def connection
      connection_without_promiscuous.tap do |connection|
        unless defined?(connection.promiscuous_hook)
          connection.class.class_eval do
            attr_accessor :current_transaction_id

            if self.name == "ActiveRecord::ConnectionAdapters::PostgreSQLAdapter"
              include ActiveRecord::Base::PostgresSQL2PCExtensions
            end

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
      @operation_name = name
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
            transaction_context.add_write_operation(self) if !@instances.empty?
          end
        end
      end
    end

    def db_operation_and_select
      raise
    end

    def operation_payloads
      @instances.map do |instance|
        instance.promiscuous.payload(:with_attributes => self.operation.in?([:create, :update])).tap do |payload|
          payload[:operation] = self.operation
        end
      end
    end
  end

  class PromiscuousInsertOperation < PromiscousOperation
    def initialize(arel, name, pk, id_value, sequence_name, binds, options={})
      super(arel, name, binds, options)
      @pk = pk
      @id_value = id_value
      @sequence_name = sequence_name
      @operation = :create
      raise unless @arel.is_a?(Arel::InsertManager)
    end

    def db_operation_and_select
      # XXX This is only supported by Postgres and should be in the postgres driver

      @connection.exec_insert("#{@connection.to_sql(@arel, @binds)} RETURNING *", @operation_name, @binds).tap do |result|
        @instances = result.map { |row| model.instantiate(row) }
      end
      # TODO Use correct primary key
      @instances.first.id
    end
  end

  class PromiscuousUpdateOperation < PromiscousOperation
    def initialize(arel, name, binds, options={})
      super
      @operation = :update
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

    def db_operation_and_select
      # TODO this should be in the postgres driver (to also leverage the cache)
      @connection.exec_query("#{@connection.to_sql(@arel, @binds)} RETURNING *", @operation_name, @binds).tap do |result|
        @instances = result.map { |row| model.instantiate(row) }
      end.rows.size
    end

    def execute(&db_operation)
      return db_operation.call unless model
      return db_operation.call unless any_published_field_changed?
      super
    end
  end

  class PromiscuousDeleteOperation < PromiscousOperation
    def initialize(arel, name, binds, options={})
      super
      @operation = :destroy
      raise unless @arel.is_a?(Arel::DeleteManager)
    end

    def db_operation_and_select
      # TODO We only need the tracked attributes really (most likely, we just need ID)
      # XXX This is only supported by Postgres.
      @connection.exec_query("#{@connection.to_sql(@arel, @binds)} RETURNING *", @operation_name, @binds).tap do |result|
        @instances = result.map { |row| model.instantiate(row) }
      end.rows.size
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
      query.prepare      { @connection.prepare_db_transaction }
      query.instrumented { @connection.commit_prepared_db_transaction(@transaction_id) }
      super
    end

    def self.recover_transaction(connection, transaction_id)
      op = new(:connection => connection, :transaction_id => transaction_id)
      # Getting the lock will trigger the real recovery mechanism
      if op.acquire_op_lock
        op.release_op_lock
      end

      # In the event where the recovery payload wasn't found, we must roll back.
      # If the operation was recoverable, but couldn't be recovered, an
      # exception would be thrown, so we won't roll it back by mistake.
      # If the operation was recovered, the roll back will result in an error,
      # which is fine.
      connection.rollback_prepared_db_transaction(transaction_id)
    end
  end
end
