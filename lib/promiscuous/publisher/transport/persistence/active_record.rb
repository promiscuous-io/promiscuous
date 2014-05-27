class Promiscuous::Publisher::Transport::Persistence::ActiveRecord
  def save(batch)
    check_schema

    q = "INSERT INTO #{table} (\"batch\") " +
      "VALUES ('#{batch.dump}') RETURNING id"

    result = connection.exec_query(q, 'Promiscuous Recovery Save')

    batch.id = result.rows.first.first.to_i
  end

  def expired
    check_schema

    q = "SELECT id, p.batch FROM #{table} p " +
      "WHERE at < current_timestamp - #{Promiscuous::Config.recovery_timeout} * INTERVAL '1 second'"

    connection.exec_query(q, 'Promiscuous Recovery Expired').rows
  end

  def delete(batch)
    check_schema

    q = "DELETE FROM #{table} WHERE id = #{batch.id}"

    connection.exec_query(q, 'Promiscuous Recovery Delete')
  end

  private

  def check_schema
    return if @schema_checked

    unless connection.table_exists?(table)
      raise <<-help
        Promiscuous requires the following migration to be run:
          create_table :_promiscuous do |t|
            t.string    :batch
            t.timestamp :at, :default => :now
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
