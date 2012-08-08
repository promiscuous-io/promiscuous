Replicable
===========

[![Build Status](http://ci.viennot.biz/crowdtap/replicable.png?branch=master)](http://ci.viennot.biz/crowdtap/replicable)

Replicable offers an automatic way of propagating your model data across one or
more applications.
It uses [RabbitMQ](http://www.rabbitmq.com/).

Usage
------

From a publisher side (app that owns the data), create a Publisher per model.
as shown below.

From your subscribers side (apps that receive updates from the publisher),
create a Subscriber per model, as shown below.

Example
--------

### In your publisher app

```ruby
# initializer
Replicable::AMQP.configure(:backend => :bunny, :app => 'crowdtap', :logger => Rails.logger,
                           :server_uri => 'amqp://user:password@host:port/vhost')

# publisher
class ModelPublisher < Replicable::Publisher::Mongoid
  publish :to => 'crowdtap/model',
          :class => Model,
          :attributes => [:field_1, :field_2, :field_3]
end
```

### In your subscriber app

```ruby
# initializer
Replicable::AMQP.configure(:backend => :rubyamqp, :app => 'sniper', :logger => Rails.logger,
                           :server_uri => 'amqp://user:password@host:port/vhost',
                           :queue_options => {:durable => true, :arguments => {'x-ha-policy' => 'all'}},
                           :error_handler => some_proc)

# subscriber
class ModelSubscriber < Replicable::Subscriber::Mongoid
  publish :from => 'crowdtap/model',
          :class => Model,
          :attributes => [:field_1, :field_2, :field_3]
end
```

### Starting the subscriber worker

    rake replicable:run[./path/to/replicable_initializer.rb]

How does it work ?
------------------

1. On the publisher side, Replicable hooks into the after_create/update/destroy callbacks.
2. When a model changes, Replicable sends a message to RabbitMQ, to the
   'replicable' [topic exchange](http://www.rabbitmq.com/tutorials/tutorial-five-python.html).
3. RabbitMQ routes the messages to each application through queues.
   We use one queue per application (TODO explain why we need one queue).
4. Subscribers apps are running the replicable worker, listening on their own queues,
   executing the create/update/destroy on their databases.

Note that we use a single exchange to preserve the ordering of data updates
across application so that subscribers always see a consistant state of the
system.

WARNING/TODO
------------

Replicable does **not** handle:
- Any of the atomic operatiors, such as inc, or add_to_set.
- Association magic. Example:
  ```ruby
  # This will NOT replicate particiation_ids:
  m = Member.first
  m.particiations = [Participation.first]
  m.save
  
  # On the other hand, this will:
  m = Member.first
  m.particiation_ids = [Participation.first.ids]
  m.save
  ```

Furthermore, it can be racy. Consider this scenario with two interleaving requests A and B:

1. (A) Update mongo doc X.value = 1
2. (B) Update mongo doc X.value = 2
3. (B) Publish 'X.value = 2' to Rabbit
4. (A) Publish 'X.value = 1' to Rabbit

At the end of the scenario, on the publisher side, the document X has value
equal to 2, while on the subscriber side, the document has a value of 1.  This
will likely not occur in most scenarios BUT BEWARE.  We have plans to fix this
issue by using version numbers and mongo's amazing findandmodify.

What's up with bunny vs ruby-amqp ?
-----------------------------------

Our publisher app does not run an eventmachine loop, which is required for
ruby-amqp. Bunny on the other hand allows a non-eventmachine based application
to publish messages to rabbitmq.

How to run the tests
--------------------

    rake appraisal:install
    rake

Compatibility
-------------

Replicable is tested against MRI 1.9.2 and 1.9.3.

Both Mongoid 2.4.x and Mongoid 3.0.x are supported.

Acknowledgments
----------------

Inspired by [Service-Oriented Design with Ruby and Rails](http://www.amazon.com/Service-Oriented-Design-Addison-Wesley-Professional-Series/dp/0321659368)

License
-------

Replicable is distributed under the MIT license.
