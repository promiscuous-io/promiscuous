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
      self.stop = true unless bareback?

      unless e.is_a?(Promiscuous::Publisher::Error)
        e = Promiscuous::Publisher::Error.new(e, nil)
      end
      Promiscuous.error "[publish] FATAL #{e} #{e.backtrace}"
      Promiscuous::Config.error_handler.try(:call, e)
    end
  end

  def replicate_collection(klass)
    return if self.stop
    # TODO Check for indexes and if not there, bail out
    while instance = klass.where(:_psp => true).find_and_modify(
                       {'$unset' => {:_psp => 1}}, :bypass_promiscuous => true)
      replicate_instance(instance)
    end
  end

  def replicate_instance(instance)
    return if self.stop
    instance.promiscuous_sync
  rescue Exception => e
    # TODO set back the psp field
    raise Promiscuous::Publisher::Error.new(e, instance)
  end
end
