module Promiscuous::Subscriber::Model
  extend ActiveSupport::Concern
  include Promiscuous::Subscriber::Envelope

  def fetch_new
    if foreign_key
      klass.new(foreign_key => id)
    else
      klass.new.tap { |o| o.id = id }
    end
  end

  def fetch_existing
    if foreign_key
      if klass.respond_to?("find_by_#{foreign_key}!")
        klass.__send__("find_by_#{foreign_key}!", id)
      elsif klass.respond_to?("find_by")
        klass.find_by(foreign_key => id)
      else
        record = klass.where(foreign_key => id).first
        raise self.class.missing_record_exception.new(klass, id) if record.nil?
        record
      end
    else
      klass.find(id)
    end
  end

  def fetch
    case operation
    when :create  then fetch_new
    when :update  then fetch_existing
    when :destroy then fetch_existing
    end
  end

  def process_attributes?
    operation != :destroy
  end

  def process
    super
    case operation
    when :create  then instance.save!
    when :update  then instance.save!
    when :destroy then instance.destroy
    end
  end

  included do
    use_option :foreign_key

    use_payload_attribute :id
    use_payload_attribute :operation, :symbolize => true
  end
end
