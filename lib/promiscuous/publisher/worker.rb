class Promiscuous::Publisher::Worker
  include Promiscuous::Common::Worker

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

      unless e.is_a?(Promiscuous::Error::Publisher)
        e = Promiscuous::Error::Publisher.new(e)
      end

      Promiscuous.error "[publish] #{e} #{e.backtrace.join("\n")}"
      Promiscuous::Config.error_notifier.try(:call, e)
    end
  end

  def replicate_collection(klass)
    loop do
      break if self.stop

      instance = klass.where(:_psp => true).
                   find_and_modify({'$unset' => {:_psp => 1}}, :bypass_promiscuous => true)
      break unless instance

      replicate_instance(instance)
    end
  end

  def replicate_instance(instance)
    instance.promiscuous_sync
  rescue Exception => e
    out_of_sync = false
    begin
      # The following update will set the _psp flag to true again,
      # effectively requeuing the publish action.
      instance.class.where(instance.atomic_selector).update({})
    rescue
      # Swallow exception of a failed recovery.
      # The user needs to manually resync.
      out_of_sync = true
    end

    raise Promiscuous::Error::Publisher.new(e, :instance    => instance,
                                               :out_of_sync => out_of_sync)
  end
end
