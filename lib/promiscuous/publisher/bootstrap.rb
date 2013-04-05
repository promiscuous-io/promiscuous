class Promiscuous::Publisher::Bootstrap
  def initialize(options={})
    @data_bootstrap = Data.new(options)
    @version_bootstrap = Version.new
  end

  def bootstrap
    @data_bootstrap.bootstrap
    @version_bootstrap.bootstrap
  end

  class Data
    def initialize(options={})
      @models = options[:models]
      @models ||= Promiscuous::Publisher::Model.publishers.values
                   .reject { |publisher| publisher.include? Promiscuous::Publisher::Model::Ephemeral }
                   .reject { |publisher| publisher.publish_to =~ /^__promiscuous__\// }
    end

    # TODO DRY this up
    LOCK_OPTIONS = { :timeout => 1.year,
                     :sleep   => 0.1,
                     :expire  => 1.minute }

    def self.lock_options
      LOCK_OPTIONS.merge({ :lock_set => Promiscuous::Key.new(:pub).join('lock_set').to_s })
    end

    def bootstrap
      @models.each do |model|
        model.all.each do |instance|
          dep = instance.promiscuous.tracked_dependencies.first
          binding.pry unless dep

          v = instance[Promiscuous::Publisher::Operation::Base::VERSION_FIELD]
          unless v
            options = self.class.lock_options.merge(:node => dep.redis_node)
            mutex = Promiscuous::Redis::Mutex.new(dep.key(:pub).to_s, options)

            case mutex.lock
            when :recovered then Promiscuous::Publisher::Operation::Base.recover_operation_from_lock(mutex)
            when true       then ;
            when false      then raise 'wut? a year already?'
            end

            v = dep.redis_node.get(dep.key(:pub).to_s).to_i
            mutex.unlock
          end

          dep.version = v
          payload = instance.promiscuous.payload(:with_attributes => true)
          payload[:operation] = :sync
          payload[:dependencies] = {:write => [dep]}
          Promiscuous::AMQP.publish(:key => payload[:__amqp__], :payload => MultiJson.dump(payload))
        end
      end
    end
  end

  class Version
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
        payload[:operation] = :versions
        payload[:keys] = futures.map { |i, f| "#{i}:#{f.value}" if f.value }.compact
        Promiscuous::AMQP.publish(:key => Promiscuous::Config.app, :payload => MultiJson.dump(payload))
      end
    end

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
  end
end
