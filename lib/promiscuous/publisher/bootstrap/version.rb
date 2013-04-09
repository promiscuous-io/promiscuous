class Promiscuous::Publisher::Bootstrap::Version < Promiscuous::Publisher::Bootstrap::Base
  def _bootstrap
    Promiscuous::Redis.master.nodes.each_with_index do |node, node_index|
      begin_at = 0
      chunk_size = Promiscuous::Config.bootstrap_chunk_size

      while begin_at < Promiscuous::Config.hash_size do
        end_at = [begin_at + chunk_size, Promiscuous::Config.hash_size].min
        Chunk.new(self, node, node_index, (begin_at...end_at)).fetch_and_send
        begin_at += chunk_size
      end
    end
  end

  class Chunk
    def initialize(parent, node, node_index, range)
      @parent = parent
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
      @parent.publish(:payload => MultiJson.dump(payload)) if payload[:keys].present?
    end
  end
end
