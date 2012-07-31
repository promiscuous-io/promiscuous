Replicable
===========

Replicable offers an automatic way of propagating your model data across one or
more applications.
It uses [RabbitMQ](http://www.rabbitmq.com/).

Usage
------

Simply include `include Replicable::Publisher` and use the `replicate` method in
your model as shown below.

Note that you need to explicitly list the fields that you care to replicate.

Example
--------

```ruby
# In your publisher app

Replicable::AMQP.configure(:backend => :bunny, :app => 'crowdtap',
                           :logger_level => Logger::DEBUG)

class PublisherModel
  include Mongoid::Document
  include Replicable::Publisher

  field :field_1
  field :field_2
  field :field_3

  replicate
end

# In your subscriber app

Replicable::AMQP.configure(:backend => :rubyamqp, :app => 'sniper',
                           :logger_level => Logger::DEBUG)

class SubscriberModel
  include Mongoid::Document
  include Replicable::Subscriber

  replicate :from => 'crowdtap', :class_name => 'publisher_model' do
    field :field_1
    field :field_2
    field :field_3
  end
end

# Starting the worker

rake replicable:run[./path/to/replicable_initializer.rb]

```

Protocol
--------

TODO

Compatibility
-------------

Replicable is tested against MRI 1.9.3.

Both Mongoid 2.4.x and Mongoid 3.0.x are supported.

Acknowledgments
----------------

[Service-Oriented Design with Ruby and Rails](http://www.amazon.com/Service-Oriented-Design-Addison-Wesley-Professional-Series/dp/0321659368)

License
-------

Replicable is distributed under the MIT license.
