class Promiscuous::Publisher::Transport::Persistence::ActiveRecord
  def save(batch)
    check_schema

    q = "INSERT INTO #{table} (batch) " +
      "VALUES ('#{batch.dump}')"

    batch.id = connection.insert_sql(q, 'Promiscuous Recovery Save')
  end

  def expired
    check_schema

    q = "SELECT id, p.batch FROM #{table} p " +
      "WHERE at < CURRENT_TIMESTAMP - INTERVAL '#{Promiscuous::Config.recovery_timeout}' second"

    connection.exec_query(q, 'Promiscuous Recovery Expired').rows
  end

  def delete(batch)
    check_schema

    q = "DELETE FROM #{table} WHERE id = #{batch.id}"

    connection.exec_delete(q, 'Promiscuous Recovery Delete', [])
  end

  private

  def check_schema
    return if @schema_checked

    unless connection.table_exists?(table)
      raise <<-help
        Promiscuous requires the following migration to be run:
          create_table :_promiscuous do |t|
            t.text      :batch
            t.timestamp :at, 'TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP'
          end
      help
    end

    @schema_checked = true
  end

  def connection
    ActiveRecord::Base.connection
  end

  def table
    Promiscuous::Config.transport_collection
  end
end
