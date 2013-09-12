class Promiscuous::Publisher::Operation::Atomic < Promiscuous::Publisher::Operation::Base
  def validate_acquired_op_lock
    return true if operation == :create
    # We need to lock and update all the dependencies before any other
    # readers can see our write through any one of our tracked attributes.

    # We want to reload the instance to make sure we have all the locked
    # dependencies that we need on secondary attribues. Or maybe we locked
    # an instance that no longer match our selector.
    # If the selector doesn't fetch any instance, the query has no effect
    # so we can bypass it as if nothing happened.  If reload_instance
    # raises an exception, it's okay to let it bubble up since we haven't
    # touch anything yet except for the locks (which will be unlocked on
    # the way out)
    #
    # There is a bit of room for optimization if we know that we don't have
    # any tracked attributes on the model and our selector is already an id.
    return true unless reload_instance

    # If reload_instance changed the current instance because the selector,
    # we need to unlock the old instance, lock this new instance, and
    # retry.
    return !reload_instance_dependencies
  end

  # XXX TODO DEAL WITH ARRAYS
  # def execute_non_persistent(&db_operation
    # # We are getting here in the following cases:
    # # * read: we fetch the instance. It's the driver's job to cache the
    # #       raw instance and return it during db_operation.
    # # * multi read: nothing to do, we'll keep our current selector, sadly
    # # TODO Get dependencies on the returned array instead of the selector set.

    # if read? && single?
      # # If the query misses, we don't bother
      # return nil unless reload_instance
      # use_id_selector
    # end

    # super
  # end

  def execute_persistent_locked(&db_operation)
    # We are going to commit all the pending writes in the context if we are
    # doing a transaction commit. We also commit the current write operation for
    # atomic writes without transactions.  We enable the recovery mechanism by
    # having someone expiring our lock if we die in the middle.

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
      stash_version_in_write_query
    when :update
      stash_version_in_write_query
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

    # Perform the actual database query (single write or transaction commit).
    # If successful, the result goes in @result, otherwise, @exception contains
    # the thrown exception.
    # XXX TODO we need to interpret the exception, if it's a network issue, we
    # should commit suicide.
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

    ensure_op_still_locked

    generate_payload
    clear_previous_operations

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

  def stash_version_in_write_query
    # Overridden to update the query to set 'instance.VERSION_FIELD = @instance_version'
  end

  def use_id_selector(options={})
    # Overridden to use the {:id => @instance.id} selector.
    # if use_atomic_version_selector is passed, the driver must
    # add the VERSION_FIELD selector if present in original instance.
  end
end
