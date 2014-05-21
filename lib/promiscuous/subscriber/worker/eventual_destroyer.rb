class Promiscuous::Subscriber::Worker::EventualDestroyer
  def start
    @thread ||= Thread.new { main_loop }
  end

  def stop
    @thread.try(:kill)
    @thread = nil
  end

  def self.check_every
    Promiscuous::Config.destroy_check_interval + rand(Promiscuous::Config.destroy_check_interval)
  end

  def main_loop
    loop do
      begin
        PendingDestroy.next(Promiscuous::Config.destroy_timeout).each(&:perform)
      rescue Exception => e
        Promiscuous.warn "[eventual destroyer] #{e}\n#{e.backtrace.join("\n")}"
        Promiscuous::Config.error_notifier.call(e)
      end

      sleep self.class.check_every.to_f
    end
  end

  def self.postpone_destroy(model, id)
    PendingDestroy.create(:class_name => model.to_s, :instance_id => id)
  end

  class PendingDestroy
    attr_accessor :class_name, :instance_id

    def perform
      model = class_name.constantize
      begin
        model.__promiscuous_fetch_existing(instance_id).destroy
      rescue model.__promiscuous_missing_record_exception
      end

      self.destroy
    end

    def destroy
      self.class.redis.zrem(self.class.key, @raw)
    end

    def initialize(raw)
      params = MultiJson.load(raw).with_indifferent_access

      @class_name  = params[:class_name]
      @instance_id = params[:instance_id]
      @raw         = raw
    end

    def self.next(timeout)
      redis.zrangebyscore(key, 0, timeout.seconds.ago.utc.to_i).map do |raw|
        self.new(raw)
      end
    end

    def self.create(options)
      redis.zadd(key, Time.now.utc.to_i, options.to_json)
    end

    def self.count
      redis.zcard(key)
    end

    private

    def self.redis
      Promiscuous::Redis.master.nodes.first
    end

    def self.key
      Promiscuous::Key.new(:sub).join('eventualdestroyer:jobs')
    end
  end
end
