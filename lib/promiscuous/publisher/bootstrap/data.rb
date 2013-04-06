class Promiscuous::Publisher::Bootstrap::Data
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
        payload[:operation] = :bootstrap_data
        payload[:dependencies] = {:write => [dep]}
        Promiscuous::AMQP.raw_publish(:key => payload[:__amqp__], :payload => MultiJson.dump(payload))
      end
    end
  end
end
