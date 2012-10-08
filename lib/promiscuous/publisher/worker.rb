class Promiscuous::Publisher::Worker
  include Promiscuous::Common::Worker

  def self.poll_delay
    # TODO Configurable globally
    # TODO Configurable per publisher
    1.second
  end

  def replicate
    EM.defer proc { self.replicate_once },
             proc { EM::Timer.new(self.class.poll_delay) { replicate } }
  end

  def replicate_once
    return if self.stop
    begin
      self.unit_of_work do
        Promiscuous::Publisher::Mongoid::Defer.klasses.values.each do |klass|
          replicate_collection(klass)
        end
      end
    rescue Exception => e
      self.stop = true
      unless e.is_a?(Promiscuous::Publisher::Error)
        e = Promiscuous::Publisher::Error.new(e, nil)
      end
      Promiscuous.error "[publish] FATAL #{e}"
      Promiscuous::Config.error_handler.try(:call, e)
    end
  end

  def replicate_collection(klass)
    return if self.stop
    psp_field = klass.aliased_fields["promiscous_sync_pending"]
    while instance = klass.where(psp_field => true).find_and_modify({'$unset' => {psp_field => 1}})
      replicate_instance(instance)
    end
  end

  def replicate_instance(instance)
    return if self.stop
    instance.class.promiscuous_publisher.new(:instance => instance, :operation => :update, :defer => false).publish
  rescue Exception => e
    raise Promiscuous::Publisher::Error.new(e, instance)
  end
end
