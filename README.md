Replicable
===========

Replicable offers an automatic way of propagating your model data across one or
more distributed applications.
It uses [RabbitMQ](http://www.rabbitmq.com/).

Usage
------

Simply include `include Replicable::Primary` and use the `replicate` method in
your model as shown below.

Note that you need to explicitly list the fields that you care to replicate.

Example
--------

```ruby
class Model
  include Mongoid::Document
  include Replicable::Primary

  field :parent_field_1
  field :parent_field_2
  field :parent_field_3

  replicate :parent_field_1, :parent_field_2
end
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
