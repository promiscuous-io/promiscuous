class Promiscuous::Subscriber::Worker::EventualDestroyer
  def start
    @thread ||= Thread.new { main_loop }
  end

  def stop
    @thread.try(:kill)
    @thread = nil
  end

  def self.destroy_timeout
    1.hour
  end

  def self.check_every
    (10 + rand(10)).minutes
  end

  def main_loop
    loop do
      begin
        PendingDestroy.where(:created_at.gt => self.class.destroy_timeout.ago.utc).each(&:perform)
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
    include Mongoid::Document
    store_in :collection => "promiscuous_pending_destroy"

    field :created_at, :default => ->{ Time.now.utc }
    field :class_name
    field :instance_id

    def perform
      model = class_name.constantize
      begin
        model.__promiscuous_fetch_existing(instance_id).destroy
      rescue model.__promiscuous_missing_record_exception
      end
      self.destroy
    end
  end
end
