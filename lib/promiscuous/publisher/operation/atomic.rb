class Promiscuous::Publisher::Operation::Atomic < Promiscuous::Publisher::Operation::Base
  # XXX instance can be a selector representation.
  attr_accessor :instance

  def initialize(options={})
    super
    @instance = options[:instance]
  end

  def acquire_op_lock
    unless dependency_for_op_lock
      return unless reload_instance
    end

    loop do
      instance_dep = dependency_for_op_lock

      super

      return if operation == :create

      # We need to make sure that the lock we acquired matches our selector.
      # There is a bit of room for optimization if we know that we don't have
      # any tracked attributes on the model and our selector is already an id.
      return unless reload_instance

      # If reload_instance changed the current instance because the selector,
      # we need to unlock the old instance, lock this new instance, and
      # retry.
      return if instance_dep == dependency_for_op_lock

      # XXX What should we do if we are going in a live lock?
      # Sleep with some jitter?
      release_op_lock
    end
  end

  def do_database_query(query)
    case operation
    when :create
      # We don't stash the version in the document as we can't have races
      # on the same document.
    when :update
      increment_version_in_document
      # We are now in the possession of an instance that matches the original
      # selector. We need to make sure the db query will operate on it,
      # instead of the original selector.
      use_id_selector(:use_atomic_version_selector => true)
      # We need to use an atomic versioned selector to make sure that
      # if we lose the lock for a long period of time, we don't mess up
      # the record. Perhaps the operation has been recovered a while ago.
    when :destroy
      use_id_selector
    end

    # The driver is responsible to set instance to the appropriate value.
    query.call_and_remember_result(:instrumented)

    if query.failed?
      # If we get an network failure, we should retry later.
      return if recoverable_failure?(query.exception)
      @instance = nil
    end
  end

  def yell_about_missing_instance
    err = "Cannot find document. Database had a dataloss?. Proceeding anyways. #{@recovery_data}"
    e = Promiscuous::Error::Recovery.new(err)
    Promiscuous.warn "[recovery] #{e}"
    Promiscuous::Config.error_notifier.call(e)
  end

  def execute_instrumented(query)
    if recovering?
      # The DB died or something. We cannot find our instance any more :(
      # this is a problem, but we need to publish.
      yell_about_missing_instance if @instance.nil?
    else
      generate_read_dependencies
      acquire_op_lock

      if @instance.nil?
        # The selector missed the instance, bailing out.
        query.call_and_remember_result(:non_instrumented)
        return
      end
    end

    # All the versions are updated and a marked as pending for publish in Redis
    # atomically in case we die before we could write the versions in the
    # database. Once incremented, concurrent queries that are reading our
    # instance will be serialized after our write, even through it may read our
    # old instance. This is a race that we tolerate.
    # XXX We also stash the document for create operations, so the recovery can
    # redo the create to avoid races when instances are getting partitioned.
    increment_read_and_write_dependencies

    # From this point, if we die, the one expiring our write locks must finish
    # the publish, either by sending a dummy, or by sending the real instance.
    # We could have die before or after the database query.

    # We save the versions in the database, as it is our source of truth.
    # This allow a reconstruction of redis in the face of failures.
    # We would also need to send a special message to the subscribers to reset
    # their read counters to the last write version since we would not be able
    # to restore the read counters (and we don't want to store them because
    # this would dramatically augment our footprint on the db).
    #
    # If we are doing a destroy operation, and redis dies right after, and
    # we happen to lost contact with rabbitmq, recovery is going to be complex:
    # we would need to do a diff from the dummy subscriber to see what
    # documents are missing on our side to be able to resend the destroy
    # message.

    do_database_query(query) unless @instance.nil?
    # We take a timestamp right after the write is performed because latency
    # measurements are performed on the subscriber.
    record_timestamp

    # This make sure that if the db operation failed because of a network issue
    # and we got recovered, we don't send anything as we could send a different
    # message than the recovery mechanism.
    ensure_op_still_locked

    generate_payload
    clear_previous_dependencies

    # As soon as we unlock the locks, the rescuer will not be able to assume
    # that the database instance is still pristine, and so we need to stash the
    # payload in redis. If redis dies, we don't care because it can be
    # reconstructed. Subscribers can see "compressed" updates.
    publish_payload_in_redis

    # TODO Performance: merge these 3 redis operations to speed things up.
    release_op_lock

    # If we die from this point on, a recovery worker can republish our payload
    # since we queued it in Redis.

    # We don't care if we lost the lock and got recovered, subscribers are
    # immune to duplicate messages.
    publish_payload_in_rabbitmq_async
  end

  def operation_payloads
    @instance.nil? ? [] : [payload_for(@instance)]
  end

  def query_dependencies
    dependencies_for(@instance)
  end

  def fetch_instance
    # This method is overridden to use the original query selector.
    # Should return nil if the instance is not found.
    @instance
  end

  def reload_instance
    @instance = fetch_instance
  end

  def increment_version_in_document
    # Overridden to increment version field in the query
  end

  def use_id_selector(options={})
    # Overridden to use the {:id => @instance.id} selector.
    # if the option use_atomic_version_selector is passed, the driver must add
    # the version_field selector.
  end

  def recoverable_failure?(exception)
    # Overridden to tell if the db exception is spurious, like a network
    # failure.
    raise
  end
end
