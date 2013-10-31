class Promiscuous::Publisher::Bootstrap::Version
  def self.bootstrap
    connection = Promiscuous::Publisher::Bootstrap::Connection.new
    Promiscuous::Redis.master.nodes.each_with_index do |node, node_index|
      begin_at = 0
      chunk_size = Promiscuous::Config.bootstrap_chunk_size

      while begin_at < Promiscuous::Config.hash_size do
        end_at = [begin_at + chunk_size, Promiscuous::Config.hash_size].min
        Chunk.new(connection, node, node_index, (begin_at...end_at)).fetch_and_send
        begin_at += chunk_size
      end
    end
  ensure
    connection.close
  end

  class Chunk
    def initialize(connection, node, node_index, range)
      @connection = connection
      @node = node
      @range = range
      @node_index = node_index
    end

    def fetch_and_send
      num_nodes = Promiscuous::Redis.master.nodes.size

      futures = {}
      @node.pipelined do
        @range.each do |i|
          next unless i % num_nodes == @node_index
          futures[i] = @node.get(Promiscuous::Key.new(:pub).join(i, 'rw'))
        end
      end

      payload = {}
      payload[:__amqp__] = Promiscuous::Config.app
      payload[:operation] = :bootstrap_versions
      payload[:keys] = futures.map { |i, f| "#{i}:#{f.value}" if f.value }.compact
      @connection.publish(:payload => MultiJson.dump(payload)) if payload[:keys].present?
    end
  end
end
