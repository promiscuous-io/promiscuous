class Promiscuous::Subscriber::Operation::Base
  attr_accessor :model, :id, :operation, :attributes
  delegate :message, :to => :message_processor

  def initialize(payload)
    if payload.is_a?(Hash)
      self.id         = payload['id']
      self.operation  = payload['operation'].try(:to_sym)
      self.attributes = payload['attributes']
      self.model      = self.get_subscribed_model(payload) if payload['types']
    end
  end

  def get_subscribed_model(payload)
    [message.app, '*'].each do |app|
      app_mapping = Promiscuous::Subscriber::Model.mapping[app] || {}
      payload['types'].to_a.each do |ancestor|
        model = app_mapping[ancestor]
        return model if model
      end
    end
    nil
  end

  def warn(msg)
    Promiscuous.warn "[receive] #{msg} #{message.payload}"
  end

  def create(options={})
    model.__promiscuous_fetch_new(id).tap do |instance|
      instance.__promiscuous_update(self)
      instance.save!
    end
  rescue Exception => e
    # TODO Abstract the duplicated index error message
    dup_index_error = true if defined?(Mongoid) && e.message =~ /E11000/
    dup_index_error = true if defined?(ActiveRecord) && e.is_a?(ActiveRecord::RecordNotUnique)

    if dup_index_error
      if options[:upsert]
        update
      else
        warn "ignoring already created record"
      end
    else
      raise e
    end
  end

  def update
    model.__promiscuous_fetch_existing(id).tap do |instance|
      instance.__promiscuous_update(self)
      instance.save!
    end
  rescue model.__promiscuous_missing_record_exception
    warn "upserting #{message.payload}"
    create
  end

  def destroy
    model.__promiscuous_fetch_existing(id).tap do |instance|
      instance.destroy
    end
  rescue model.__promiscuous_missing_record_exception
    warn "ignoring missing record"
  end
end
