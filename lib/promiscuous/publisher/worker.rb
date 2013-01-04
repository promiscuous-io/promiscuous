class Promiscuous::Publisher::Worker
  include Promiscuous::Common::Worker

  attr_accessor :recovered

  def self.poll_delay
    # TODO Configurable globally
    # TODO Configurable per publisher
    1.second
  end

  def check_indexes
    Promiscuous::Publisher::Mongoid::Defer.klasses.values.each do |klass|
      unless klass.collection.indexes.any? { |i| i['key'].keys.include? '_psp' }
        raise 'Please run rake db:mongoid:create_indexes'
      end
    end
  end

  def replicate
    check_indexes
    EM::PeriodicTimer.new(self.class.poll_delay) { self.replicate_once }
  end

  def replicate_once
    return if self.stop
    begin
      self.unit_of_work('publisher') do
        Promiscuous::Publisher::Mongoid::Defer.klasses.values.each do |klass|
          replicate_collection(klass)
        end
      end
    rescue Exception => e
      self.stop = true unless bareback?

      unless e.is_a?(Promiscuous::Publisher::Error)
        e = Promiscuous::Publisher::Error.new(e, nil)
      end

      if self.recovered
        Promiscuous.warn "[publish] will retry #{e.instance.try(:id)} #{e} #{e.backtrace}"
      else
        Promiscuous.error "[publish] FATAL #{e.instance.try(:id)} #{e} #{e.backtrace}"
      end

      Promiscuous::Config.error_handler.try(:call, e)
    end
  end

  def replicate_collection(klass)
    loop do
      break if self.stop

      self.recovered = false
      instance = klass.where(:_psp => true).
                   find_and_modify({'$unset' => {:_psp => 1}}, :bypass_promiscuous => true)
      break unless instance

      replicate_instance(instance)
    end
  end

  def replicate_instance(instance)
    instance.promiscuous_sync
  rescue Exception => e
    # We failed publishing. Best effort recover.
    if e.is_a?(Promiscuous::Publisher::Error)
      e.instance = instance
    else
      e = Promiscuous::Publisher::Error.new(e, instance)
    end

    begin
      # The following update will set the _psp flag to true again, effectively
      # requeuing the publish action.
      instance.class.where(instance.atomic_selector).update({})
      self.recovered = true
    rescue
      # Swallow exception of a failed recovery, the log file will have a FATAL entry.
      # The user needs to manually resync.
    end

    raise e
  end
end
