class Promiscuous::Publisher::Operation::Atomic < Promiscuous::Publisher::Operation::Base
  # XXX instance can be a selector representation.
  attr_accessor :instance

  def initialize(options={})
    super
    @instance = options[:instance]
  end

  def operation_payloads
    op = self.failed? ? :dummy : self.operation
    instance_payload = @instance.promiscuous.payload(:with_attributes => op.in?([:create, :update]))
    instance_payload[:operation] = op
    [instance_payload]
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

  def execute_persistent_locked(&db_operation)
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

    case operation
    when :create
      stash_version_in_write_query(@committed_write_deps.first.version)
    when :update
      stash_version_in_write_query(@committed_write_deps.first.version)
      # We are now in the possession of an instance that matches the original
      # selector. We need to make sure the db_operation will operate on it,
      # instead of the original selector.
      use_id_selector(:use_atomic_version_selector => true)
      # We need to use an atomic versioned selector to make sure that
      # if we lose the lock for a long period of time, we don't mess up
      # with other people's updates. Also we make sure that the recovery
      # mechanism is not racing with us.
    when :destroy
      use_id_selector(:use_atomic_version_selector => true)
    end

    # Perform the actual database query.
    # If successful, the result goes in @result, otherwise, @exception contains
    # the thrown exception.
    perform_db_operation_with_no_exceptions(&db_operation)

    # We take a timestamp right after the write is performed because latency
    # measurements are performed on the subscriber.
    record_timestamp

    if operation == :update && !failed?
      # The underlying driver should implement some sort of find and modify
      # operation in the previous write query to avoid this extra read query,
      # and let us access the instance through fetch_instance called from
      # reload_instance.
      # If reload_instance raise an exception, we let it bubble up,
      # and we'll trigger the recovery mechanism.
      use_id_selector
      reload_instance
    end

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

  def stash_version_in_write_query(version)
    # Overridden to update the query to set the version field with:
    # instance[Promiscuous::Config.version_field] = version
  end

  def use_id_selector(options={})
    # Overridden to use the {:id => @instance.id} selector.
    # if the option use_atomic_version_selector is passed, the driver must add
    # the version_field selector.
  end
end
