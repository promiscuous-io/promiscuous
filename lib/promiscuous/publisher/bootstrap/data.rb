class Promiscuous::Publisher::Bootstrap::Data
  def initialize(options={})
    @models = options[:models]
    @models ||= Promiscuous::Publisher::Model.publishers.values
                  .reject { |publisher| publisher.include? Promiscuous::Publisher::Model::Ephemeral }
                  .reject { |publisher| publisher.publish_to =~ /^__promiscuous__\// }
  end

  def lock_options
    @@lock_options ||= {
      :timeout  => 1.year,   # wait forever.
      :sleep    => 1.second, # polling every second. No need to be aggressive, it would distrub real traffic.
      :expire   => 1.minute, # after one minute, we are considered dead
      :lock_set => Promiscuous::Key.new(:pub).join('lock_set').to_s
    }
  end

  def bootstrap
    @models.each do |model|
      model.all.each do |instance|
        dep = instance.promiscuous.tracked_dependencies.first
        # TODO Abstract DB operation (is [] Mongoid only?)
        dep.version = instance[Promiscuous::Publisher::Operation::Base::VERSION_FIELD].to_i
        payload = instance.promiscuous.payload
        payload[:operation] = :bootstrap_data
        payload[:dependencies] = {:write => [dep]}
        Promiscuous::AMQP.publish(:key => payload[:__amqp__], :payload => MultiJson.dump(payload))
      end
    end
  end
end
