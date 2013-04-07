class Promiscuous::Publisher::Bootstrap::Version
  def bootstrap
    Promiscuous::Redis.master.nodes.each_with_index do |node, node_index|
      begin_at = 0

      while begin_at < Promiscuous::Config.hash_size do
        end_at = [begin_at + Promiscuous::Config.bootstrap_chunk_size, Promiscuous::Config.hash_size].min
        Chunk.new(node, node_index, (begin_at...end_at)).fetch_and_send
        begin_at += 1000
      end
    end
  end

  class Chunk
    def initialize(node, node_index, range)
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
      payload[:operation] = :bootstrap_versions
      payload[:keys] = futures.map { |i, f| "#{i}:#{f.value}" if f.value }.compact
      Promiscuous::AMQP.publish(:key => Promiscuous::Config.app, :payload => MultiJson.dump(payload))
    end
  end
end
