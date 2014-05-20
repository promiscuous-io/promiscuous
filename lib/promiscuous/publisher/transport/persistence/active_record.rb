class Promiscuous::Publisher::Transport::Persistence::ActiveRecord
  def save(batch)
    q = "INSERT INTO #{table} (\"batch\") " +
      "VALUES ('#{batch.dump}') RETURNING id"

    result = connection.exec_query(q, 'Promiscuous Recovery Save')

    batch.id = result.rows.first.first.to_i
  end

  def expired
    q = "SELECT id, p.batch FROM #{table} p " +
      "WHERE at < current_timestamp - #{Promiscuous::Config.recovery_timeout} * INTERVAL '1 second'"

    connection.exec_query(q, 'Promiscuous Recovery Expired').rows
  end

  def delete(batch)
    q = "DELETE FROM #{table} WHERE id = #{batch.id}"

    connection.exec_query(q, 'Promiscuous Recovery Delete')
  end

  private

  def connection
    ActiveRecord::Base.connection
  end

  def table
    Promiscuous::Config.transport_collection
  end
end
