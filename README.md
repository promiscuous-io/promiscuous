Promiscuous
===========

[![Build Status](https://secure.travis-ci.org/crowdtap/promiscuous.png?branch=master)](https://secure.travis-ci.org/crowdtap/promiscuous)

Promiscuous offers an automatic way of propagating your model data across one or
more applications. It supports Mongoid2, Mongoid3 and ActiveRecord.
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
Promiscuous::AMQP.configure(:app => 'crowdtap',
                            :server_uri => 'amqp://user:password@host:port/vhost')

# publisher
class ModelPublisher < Promiscuous::Publisher::Mongoid
  publish :to => 'crowdtap/model',
          :class => Model,
          :attributes => [:field_1, :field_2, :field_3]
end
```

### In your subscriber app

```ruby
# initializer
Promiscuous::AMQP.configure(:app => 'sniper',
                            :server_uri => 'amqp://user:password@host:port/vhost',
                            :error_handler => some_proc)

# subscriber
class ModelSubscriber < Promiscuous::Subscriber::Mongoid
  subscribe :from => 'crowdtap/model',
            :class => Model,
            :attributes => [:field_1, :field_2, :field_3]
end
```

### Starting the subscriber worker

    rake promiscuous:replicate

How does it work ?
------------------

1. On the publisher side, Promiscuous hooks into the after_create/update/destroy callbacks.
2. When a model changes, Promiscuous sends a message to RabbitMQ, to the
   'promiscuous' [topic exchange](http://www.rabbitmq.com/tutorials/tutorial-five-python.html).
3. RabbitMQ routes the messages to each application through queues.
   We use one queue per application (TODO explain why we need one queue).
4. Subscribers apps are running the promiscuous worker, listening on their own queues,
   executing the create/update/destroy on their databases.

Note that we use a single exchange to preserve the ordering of data updates
across application so that subscribers always see a consistant state of the
system.

WARNING/TODO
------------

Promiscuous does **not** handle:
- ActiveRecord polymorphism.
- Any of the Mongoid atomic operatiors, such as inc, or add_to_set.
- Mixing databases (ActiveRecord <=> Mongoid) because of the id format mismatch.
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

Furthermore, it can be racy. Consider this scenario with two interleaving
requests A and B:

1. (A) Update mongo doc X.value = 1
2. (B) Update mongo doc X.value = 2
3. (B) Publish 'X.value = 2' to Rabbit
4. (A) Publish 'X.value = 1' to Rabbit

At the end of the scenario, on the publisher side, the document X has value
equal to 2, while on the subscriber side, the document has a value of 1.  This
will likely not occur in most scenarios BUT BEWARE.  We have plans to fix this
issue by using version numbers and mongo's amazing findandmodify.

Backend: bunny / ruby-amqp
--------------------------

Your publisher app may not run an eventmachine loop, which is required for
ruby-amqp. Bunny on the other hand allows a non-eventmachine based application
to publish messages to rabbitmq.

Compatibility
-------------

Promiscuous is tested against MRI 1.9.2 and 1.9.3.

ActiveRecord, Mongoid 2.4.x and Mongoid 3.0.x are supported.

License
-------

Promiscuous is distributed under the MIT license.
