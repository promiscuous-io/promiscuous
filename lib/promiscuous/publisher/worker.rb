class Promiscuous::Publisher::Worker
  include Promiscuous::Common::Worker

  def self.poll_delay
    # TODO Configurable globally
    # TODO Configurable per publisher
    1.second
  end

  def initialize(options={})
    super
    check_indexes
  end

  def check_indexes
    Promiscuous::Publisher::Mongoid::Defer.klasses.values.each do |klass|
      unless klass.collection.indexes.any? { |i| i['key'].keys.include? '_psp' }
        raise 'Please run rake db:mongoid:create_indexes'
      end
    end
  end

  def resume
    @timer ||= EM::PeriodicTimer.new(self.class.poll_delay) { self.replicate_once }
    super
  end

  def stop
    @timer.try(:cancel)
    @timer = nil
    super
  end

  def replicate_once
    return if self.stopped?

    self.unit_of_work('publisher') do
      maybe_rescue_instance
      replicate_all_collections
    end
  rescue Exception => e
    unless e.is_a?(Promiscuous::Error::Publisher)
      e = Promiscuous::Error::Publisher.new(e)
    end

    retry_msg = stop_for_a_while(e)
    Promiscuous.warn "[publish] (#{retry_msg}) #{e} #{e.backtrace.join("\n")}"

    if e.out_of_sync
      Promiscuous.error "[publish] WARNING out of sync on #{e.instance.inspect}"
      @out_of_sync_instance = e.instance
    end

    Promiscuous::Config.error_notifier.try(:call, e)
  end

  def replicate_all_collections
    Promiscuous::Publisher::Mongoid::Defer.klasses.values.each do |klass|
      replicate_collection(klass)
    end
    made_progress
  end

  def replicate_collection(klass)
    loop do
      break if self.stopped?

      instance = klass.where(:_psp => true).
                   find_and_modify({'$unset' => {:_psp => 1}}, :bypass_promiscuous => true)
      break unless instance

      replicate_instance(instance)
    end
  end

  def replicate_instance(instance)
    instance.promiscuous_sync
    made_progress
  rescue Exception => e
    out_of_sync = requeue_instance(instance)
    raise Promiscuous::Error::Publisher.new(e, :instance    => instance,
                                               :out_of_sync => out_of_sync)
  end

  def requeue_instance(instance)
    # The following update will set the _psp flag to true again,
    # effectively requeuing the publish action.
    instance.class.where(instance.atomic_selector).update({})
    false
  rescue Exception
    # Swallow exception of a failed recovery.
    # The user needs to manually resync.
    true
  end

  def maybe_rescue_instance
    return unless @out_of_sync_instance
    replicate_instance(@out_of_sync_instance)
    @out_of_sync_instance = nil
  end
end
