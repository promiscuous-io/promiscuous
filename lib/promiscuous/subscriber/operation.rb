class Promiscuous::Subscriber::Operation
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

  def message_processor
    @message_processor ||= Promiscuous::Subscriber::MessageProcessor.current
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
    if e.message =~ /E11000/ ||
       e.is_a?(ActiveRecord::RecordNotUnique) # TODO Ensure that it's on the pk AND only check if ActiveRecord is defined
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

  # XXX Bootstrapping is a WIP. Here's what's left to do:
  # - Promiscuous::Subscriber::Operation#bootstrap_missing_data is not implemented
  #   properly (see comment in code)
  # - Implementing pass3 to avoid upserts
  # - Automatic switching from pass1, pass2, pass3, live
  # - Unbinding the bootstrap exchange when going live, and reset prefetch
  #   during the version bootstrap phase.
  # - CLI interface and progress bars

  def bootstrap_versions
    operations = message.parsed_payload['operations']

    operations.map { |op| op['keys'] }.flatten.map { |k| Promiscuous::Dependency.parse(k, :owner => message.app) }.group_by(&:redis_node).each do |node, deps|
      node.mset(deps.map { |dep| [dep.key(:sub).join('rw').to_s, dep.version] }.flatten)
    end
  end

  def bootstrap_data
    dep = message.dependencies.first
    if dep.version <= dep.redis_node.get(dep.key(:sub).join('rw').to_s).to_i
      create(:upsert => true)
    else
      # We don't save the instance if we don't have a matching version in redis.
      # It would mean that the document got update since the bootstrap_versions.
      # We'll get it on the next pass. But we should remember what we've dropped
      # to be able to know when we can go live
    end
  end

  def bootstrap_missing_data
    # TODO XXX How do we know what is the earliest instance?
    # TODO Remember what instances we've dropped (the else block in the
    # bootstrap_data method)
    create(:upsert => true)
  end

  def on_bootstrap_operation(wanted_operation, options={})
    if operation == wanted_operation
      yield
      options[:always_postpone] ? message.postpone : message.ack
    else
      message.postpone
    end
  end

  def execute
    case Promiscuous::Config.bootstrap
    when :pass1
      # The first thing to do is to receive and save an non atomic snapshot of
      # the publisher's versions.
      on_bootstrap_operation(:bootstrap_versions) { bootstrap_versions }

    when :pass2
      # Then we move on to save the raw data, but skipping the message if we get
      # a mismatch on the version.
      on_bootstrap_operation(:bootstrap_data) { bootstrap_data }

    when :pass3
      # Finally, we create the rows that we've skipped, we postpone them to make
      # our lives easier. We'll detect the message as duplicates when re-processed.
      # on_bootstrap_operation(:update, :always_postpone => true) { bootstrap_missing_data if model }
      # TODO unbind the bootstrap exchange
    else
      case operation
      when :create  then create  if model
      when :update  then update  if model
      when :destroy then destroy if model
      else raise "Invalid operation received: #{operation}"
      end
    end
  end
end
