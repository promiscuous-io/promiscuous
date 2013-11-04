class Promiscuous::Subscriber::Operation::Bootstrap < Promiscuous::Subscriber::Operation::Base
  # XXX Bootstrapping is a WIP. Here's what's left to do:
  # - Automatic switching from pass1, pass2, live
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
      raise "Invalid operation received: #{operation}"
    end
  end

  def message_processor
    @message_processor ||= Promiscuous::Subscriber::MessageProcessor::Bootstrap.current
  end
end
