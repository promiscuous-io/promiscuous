Replicable
===========

[![Build Status](http://ci.viennot.biz/crowdtap/replicable.png?branch=master)](http://ci.viennot.biz/crowdtap/replicable)

Replicable offers an automatic way of propagating your model data across one or
more applications.
It uses [RabbitMQ](http://www.rabbitmq.com/).

Usage
------

From a publisher side (app that owns the data), simply `include
Replicable::Publisher` and use the `replicate` method in your model as shown
below. All fields changes are broadcasted.

From your subscribers side (apps that receive updates from the publisher),
`include Replicable::Subscriber` and use a block to explicitly express the
list of fields to be replicated, as shown below.

Example
--------

### In your publisher app

```ruby
# initializer
Replicable::AMQP.configure(:backend => :bunny, :app => 'crowdtap',
                           :logger_level => Logger::DEBUG,
                           :error_handler => some_proc,
                           :server_uri => 'amqp://user:password@host:port/vhost')

# model
class PublisherModel
  include Mongoid::Document
  include Replicable::Publisher

  field :field_1
  field :field_2
  field :field_3

  replicate
end
```

### In your subscriber app

```ruby
# initializer
Replicable::AMQP.configure(:backend => :rubyamqp, :app => 'sniper',
                           :logger_level => Logger::DEBUG,
                           :error_handler => some_proc,
                           :server_uri => 'amqp://user:password@host:port/vhost')

# model
class SubscriberModel
  include Mongoid::Document
  include Replicable::Subscriber

  replicate :from => 'crowdtap', :class_name => 'publisher_model' do
    field :field_1
    field :field_2
    field :field_3
  end
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

What's up with bunny vs ruby-amqp ?
-----------------------------------

Our publisher app does not run an eventmachine loop, which is required for
ruby-amqp. Bunny on the other hand allows a non-eventmachine based application
to publish messages to rabbitmq.

How to run the tests
--------------------

    rake appraisal:install
    rake

Protocol
--------

TODO

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
