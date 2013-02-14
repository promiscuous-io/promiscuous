Promiscuous
===========

[![Build Status](https://travis-ci.org/crowdtap/promiscuous.png?branch=travis)](https://travis-ci.org/crowdtap/promiscuous)

Table of Content
----------------

* **Promiscuous**  
   [Introduction](#introduction)  
   [Rails Quick Start](#rails-quick-start)  
   [How it works](#how-it-works)  

* **Features & Recipes**  
   [Attributes](#attributes)  
   [Ephemerals & Observers](#ephemerals--observers)  
   [Polymorphism](#polymorphism)  
   [Embedded Documents](#embedded-documents)  
   [Foreign Keys](#foreign-keys)  
   [Namespace Mapping](#namespace-mapping)  
   [Promiscuous DSL](#promiscuous-dsl)  
   [How it really works](#how-it-really-works)  

* **Configuration**  
   [Configuration Options](#configuration-options)  
   [Subscriber CLI Options](#subscriber-cli-options)  

* **Testing**  
   [Unit Testing](#unit-testing)  
   [Integration Testing](#integration-testing)  
   [Gemify your apps](#gemify-your-apps)  

* **Going to Production**  
   [Initial sync](#initial-sync)  
   [Error Handling](#error-handling)  
   [Monitoring](#monitoring)  
   [Managing Deploys](#managing-deploys)  
   [Setup with Unicorn, Resque, etc.](#setup-with-unicorn-resque-etc)  

* **Miscellaneous**  
   [Roadmap](#roadmap)  
   [Coding Restrictions](#coding-restrictions)  
   [Limitations](#limitations)  
   [License](#license)  

Introduction
------------

Promiscuous is designed to facilitate designing a
[service-oriented architecture](http://en.wikipedia.org/wiki/Service-oriented_architecture)
in Ruby.

In order for a service-oriented system to be successful, services *must* be
loosely coupled. Using a common database goes against this principle. Each
service in the system has its own dedicated database. This way, each
application can denormalize and transform data at will.

Promiscuous replicates the data around the system. Each application can publish
and subscribe to application models. Promiscuous supports Mongoid3 and
ActiveRecord (partially). It relies on [RabbitMQ](http://www.rabbitmq.com/) to
distribute data around and [Redis](http://redis.io/) to synchronize and order
operations.

Promiscuous guarantees that the subscriber never sees out of order updates.
This property considerably reduce the complexity of applications.

This constraint removes any hopes of subscribing directly to the database oplog
as it wouldn't know the ordering of operations when using shards, which is
one of the limitations of [MoSQL](https://github.com/stripe/mosql).

Essentially, Promiscuous is a record/replay system built on top the ActiveModel API.
The recording is done on the publisher side, and replayed asynchronously on subscribers.

Rails Quick Tutorial
--------------------

### 1. Preparation

We need to few things for the promiscuous tutorial:

* The AMQP broker [RabbitMQ](http://www.rabbitmq.com/) 2.8.7 (not 3.x because of a bug in the ruby driver) up and running.
* The key-value storage system [Redis](http://redis.io/) up and running.
* Two rails applications with the promiscuous gem installed.
* Both applications must be running on separate databases.
* Both applications must have a User model (ActiveRecord or Mongoid) with two attributes name and email.

### 2. Publishing

By including the Promiscuous publisher mixin, we can publish the model attributes:

```ruby
# app/models/user.rb on the publisher app
class User
  include Promiscuous::Publisher
  publish :name, :email
end
```

### 3. Subscribing

Similarly to the publisher app, we can subscribe to the attributes:

```ruby
# app/models/user.rb on the subscriber app
class User
  include Promiscuous::Subscriber
  subscribe :name, :email

  after_create { Logger.info "Hi #{name}!" }
end
```

### 4. Replication

The subscriber must listen for new data to arrive. Promiscuous has a worker
that we can launch with the following command:

```
bundle exec promiscuous subscribe
```

You should start the subscriber *first*, otherwise the appropriate queues
will not be created. From now on, you should see the queue in the RabbitMQ
web admin page. Create a new user in the publisher's rails console with:

```ruby
User.create(:name => 'Yoda')`
```

You should see the message "Hi Yoda!" appearing in the log file of the subscriber.

How it works
------------

On the publisher side, Promiscuous hooks on the after\_create/update/destroy
callbacks of the published models. A change to a model triggers promiscuous to
publish a payload corresponding to the operation to the RabbitMQ message queue.
RabbitMQ then routes the payload to all the subscribers interested in that
model. When a subscriber receives a model operation, it replicates the
model operation in its environment.

Features & Recipes
==================

---

Attributes
----------

Since we are doing database replication, it's important to distinguish that
Promiscuous operates at the ActiveModel API, and thus makes no difference
between the model methods and the actual persisted attributes.
We call _virtual attributes_ computed attributes that are published. For example:

```ruby
class User
  include Promiscuous::Publisher
  publish :full_name

  def full_name
    "#{first_name} #{last_name}"
  end
end
```

Any attributes that respond to `.to_json` can be published, including array and
hashes. We do not recommend using deeply nested structures without using
embedded documents though.

On the subscriber side, Promiscuous invokes the setter corresponding to the
subscribed attribute.

Ephemerals & Observers
----------------------

In some situations, publishing data models that are not persisted to the database
can be very useful:

```ruby
# Publisher side
class UserEvent
  include Promiscuous::Publisher::Model::Ephemeral
  attr_accessor :user_id
  attr_accessor :event_name

  publish :user_id, :event_name
end

UserEvent.create(:user_id => 123, :event_name => :registered)

# Subscriber side
class UserEvent
  include Promiscuous::Subscriber::Model::Observer
  attr_accessor :user_id
  attr_accessor :event_name

  subscribe :user_id, :event_name

  after_create do
    User.find(user_id).send_email("welcome!") if event_name == :registered
  end
end
```

Promiscuous allows you to mix persisted models with ephemeral and observers.
For example, one would use a mailer application that observes the user state
attribute to send the appropriate email.

Polymorphism
-------------

When publishing a model, the class hierarchy is also published to allow the
subscriber to map classes. For example:

```ruby
# Publisher side
class User
  include Promiscuous::Publisher
  publish :name, :email
end

class Member < User
  publish :points
end

class Admin < User
  publish :role
end

# Subscriber side
class User
  include Promiscuous::Subscriber
  subscribe :name, :email
end

class Member < User
  subscribe :points
end
```

Notice that the Admin model is not subscribed. When the subscriber receives an
admin model, the subscriber looks for its nearest parent, which is the User
model, and treat the received admin as a user. Promiscuous follows polymorphism
rules by traversing the published inheritance chain to find the subscriber's
subclass. This can be quite handy to collapse a tree of subclasses at a given
node in the hierarchy tree.

Embedded Documents
------------------

Promiscuous supports embedded documents (mongoid only feature):

```ruby
class Address
  include Mongoid::Document
  include Promiscuous::Publisher

  publish :street_name, :zipcode
end

class User
  include Mongoid::Document
  include Promiscuous::Publisher
  embeds_many :addresses

  publish :name, :email, :addresses
end
```

Foreign Keys
------------

When mixing databases in the system, the primary key formats may not be compatible.
Using a foreign key with a different column can be handy in this case. Example:

```ruby
# Publisher side
class User
  include Mongoid::Document
  include Promiscuous::Publisher
  publish :name, :email
end

# Subscriber side
class User < ActiveRecord::Base
  include Promiscuous::Subscriber
  subscribe :name, :email, :foreign_key => :crowdtap_id
end
```

Namespace Mapping
-----------------

### AMQP Endpoint names

By default, Promiscuous publishes model operations to the
'app\_name/model\_name' endpoint (RabbitMQ message key).
Subscribers subscribe each of their models to '\*/model\_name'.
The '*' means that we subscribe from any application in the system.
This can be overridden with the `:to` and `:from` arguments.

```ruby
# Publisher side
class User
  include Promiscuous::Publisher
  publish :name, :email, :to => 'crowdtap/member'
end

# Subscriber side
class CrowdtapMember
  include Promiscuous::Subscriber
  subscribe :name, :email, :from => 'crowdtap/member'
end
```

### Polymorphic class names

When using polymorphism, the class names can be remapped with the `:as`
argument. Example:

```ruby
# Publisher side
class User
  include Promiscuous::Publisher
  publish :name, :email
end

class Member < User
  publish :points
end

class Admin < User
  publish :role
end

# Subscriber side
class CrowdtapUser
  include Promiscuous::Subscriber
  subscribe :from => 'crowdtap/user'
  subscribe :as   => :User
  subscribe :name, :email
end

class CrowdtapMember < CrowdtapUser
  subscribe :as => :Member
  subscribe :points
end
```
Note that using `:as` in a model collapses its descendants tree unless the
children also use the `:as` keyword.

Promiscuous DSL
---------------

There are two ways to define the publishers and subscribers attributes:
1) directly in the model as shown in the examples above 2) in a separate file.
In big applications, code organization is crucial. Depending on your
philosophy, you can pick one way or the other.

### In the model

```ruby
class User
  include Promiscuous::Publisher
  publish :to => 'crowdtap/user'
  publish :name
  publish :email
end

# Or more succinctly:
class User
  include Promiscuous::Publisher
  publish :name, :email, :to => 'crowdtap/user'
end
```

### In a config file

```ruby
# file: ./config/promiscuous.rb
Promiscuous.define do
  publish :user, :to => 'crowdtap/user' do
    attributes :name, :email
  end
end
```

In some ways, the configuration file is the analogous of the
`./config/routes.rb` file when comparing promiscuous and rails controllers.

How it really works
-------------------

### Publisher side

Promiscuous instruments the database driver to parse the write queries emitted
to the database. The write queries that correspond to published models are
passed through the promiscuous pineline. Promiscuous does not allow write
queries that touch multiple documents (or rows) at the same time.
These hooks are in [publisher/model/mongoid.rb](blob/master/lib/promiscuous/publisher/model/mongoid.rb)

1. The first thing promiscuous does is to retrieve the _id_ of the document
   that the database selector would hit.
2. Then a lock is acquired on the id of the model on the Redis server.
3. The first step is performed again to check against a race on the selector,
   ensuring that the id retrieved on step 1 still satisfies the selector.
4. The dependencies are incremented in Redis ([vector clock](http://en.wikipedia.org/wiki/Vector_clocks)).
   For the moment, there is just a global counter. The counter value is saved
   for the actual publishing.
5. The database query is finally performed on the selected document.
   Note that if the database query fails, we keep going because the
   dependencies updates cannot be undone. In case of an error, we publish
   a dummy operation for that id.
6. The document is read back from the database, and handed off to another thread
   which publishes the model payload with the counter value from step 4.
7. The lock is released

This algorithm is in [publisher/operation.rb](blob/master/lib/promiscuous/publisher/operation.rb)

Note that if a failure happens between the database update and the publishing
of the message, the system is _out-of-sync_. This means that the subscribers
will eventually deadlock because of the missing message.
Promiscuous will log a message of this nature if it detects such situation:

    FATAL (out of sync) Promiscuous::Error::Connection:
      Not connected to amqp://localhost/ while publishing #<Member email: "joe@example.com">

While very rare as Promiscuous checks for the health of the connection before
doing the database query, we are working on a mechanism that would allow any
kind of failure.

The payload that gets sent over to the subscribers looks like this:

```javascript
{
  __amqp__:  "crowdtap/user",
  id:        "511c6f589fc87e347a00001a",
  ancestors: ["Admin", "User"],
  operation: "update",
  version: { global: 231 },
  payload: {
    name:  "Joe",
    email: "joe@example.com",
    address: {
      __amqp__: "crowdtap/address",
      id:       "511c6f589fc87e347a00001b",
      payload:  {
        street_name: "96, promiscuous street",
        zipcode:     "10025"
      }
    }
  }
}
```

The payload generation code is in [publisher/model.rb](blob/master/lib/promiscuous/publisher/model.rb).
Note that the payload is database/language agnostic.

Wish list: send the before/after attributes to allow remote observers to
trigger state transitions.

### Subscriber side

Meanwhile, on the subscriber side, a worker is waiting for messages.

1.  It all starts when _the pump_ receives a message from the broker.
2.  The pump passes the received message to the _message synchronizer_ thread.
3.  The message synchronizer thread looks at the version attribute and compares
    it with the subscriber's current version counter. If there is a mismatch,
    the synchronizer subscribes to a Redis queue for a signal. If not, then
    the message is passed to a thread pool (the _runners_).
4.  A lock is taken the model id on Redis.
5.  The dependency versions are checked again to detect if we are processing an
    already processed message.
6.  The model is fetched from the database if needed (updates and destroy operations).
    If not found, Promiscuous does an _upsert_ by creating the model. It emits a
    warning in this scenario.
7.  The attributes are updated, and `save!` is performed.
8.  The dependencies are updated. We currently use a single global counter.
9.  The new version is published in the Redis queues to wake up any subscribers
    waiting for a specific message version.
10. The lock is released.
11. RabbitMQ gets notified that the message has been successfully processed.

The corresponding code can be found in:
[subscriber/worker/pump.rb](blob/master/lib/promiscuous/subscriber/worker/pump.rb),
[subscriber/worker/message_synchronizer.rb](blob/master/lib/promiscuous/subscriber/worker/message_synchronizer.rb),
[subscriber/worker/operation.rb](blob/master/lib/promiscuous/subscriber/worker/operation.rb).

Configuration
=============

---

Configuration Options
---------------------

If you use Promiscuous in production, you will most likely need to tweak the
configuration options. We recommend using an initializer like so:

```ruby
# config/initializers/promiscuous.rb
Promiscuous.configure do |config|
  # All the settings are optional, the given values are the defaults.
  # config.app            = 'inferred_from_the_rails_app_name'
  # config.amqp_url       = 'amqp://guest:guest@localhost:5672'
  # config.redis_url      = 'redis://localhost/'
  # config.backend        = :rubyamqp
  # config.logger         = Rails.logger
  # config.error_notifier = proc { |exception| nil }
end
```

You may set the backend to :null when running your test suite to use
Promiscuous in pretend mode.

Subscriber CLI Options
----------------------

The subscriber worker accepts a few arguments. The most important ones are:

* `--prefetch [NUM]` sets the maximum number of messages RabbitMQ is willing to
  sends to the worker without having them acked. If this value is too low, the
  worker can deadlock because of out of order messages.
* `--recovery`. Turns on recovery mode. When the worker has received all
  prefetchable messages and the message processing cannot go further,
  Promiscuous kicks the recovery mechanism which updates unresolved dependencies,
  effectively skipping messages.
  A warning message will be logged in this situation.
* `--bareback`. Turns on bareback mode. Promiscuous will run without enforcing
  any message ordering, and swallow all exceptions thrown. Do not use it in production.

In development mode, using `bundle exec promiscuous subscribe --prefetch 5
--recovery` is recommended to avoid deadlocks due to database reset.

Testing
========

---

Unit Testing
------------

TODO

Integration Testing
-------------------

TODO

1. Generate the mock file with `promiscuous generate mocks`
2. Export a factory with that file to subscribers
3. Use the mocks+factories in the subscribers integration tests.
   Promiscuous will inject the json payloads to your subscribers
   endpoints to emulate what will really happen.

Gemify your apps
----------------

TODO

Going to Production
====================

---

Initial sync
------------

When deploying a new subscriber, it is useful to synchronize its database
with the publisher database. Promiscuous provides two ways of synchronizing
the subscriber database.

### Programmatically

```ruby
User.each(&:promiscuous_sync)
```

Note that the `promiscuous_sync` method simply forces a publish operation.
It will not be racy with respect to other message because of the locking dance
it performs. Nevertheless, the subscriber will "see" an inconsistent
ordering of messages during the synchronization as model dependencies
are not respected.

### From the command line

```
bundle exec promiscuous publish "User.where(:updated_at.gt => 1.day.ago)" InventoryItem Orders
```

Promiscuous will publish each of these collections with a progress bar.
Note that you can partition your data with the right selectors to publish with
many workers. Partition overlapping is fine.

Furthermore, you might consider having a dummy subscriber that subscribes
to all the models keeping an always up to date database ready to be cloned for
new applications. This way you just need to synchronize the recently modified
models.

Error Handling
--------------

Promiscuous tries to reconnect every 2 seconds when the connection to RabbitMQ
or Redis has been lost. During this time, the publisher cannot perform any write
queries. To take a publisher instance out of the load balancer, Promiscuous provides
a health checker. `Promiscuous.healthly?` returns true when the system is able to
publish or subscribe to message.

On the subscriber side, when a message cannot be processed due to a raised
exception, for example because of a database failure, the message
will eventually be retried. (Current implementation: you have to restart
the worker, TODO: retry with exponential backoff)

When errors occur, the configurable `error_notifier` is invoked with the
following exceptions:

```ruby
Promiscuous::Error::Connection # Lost connection
Promiscuous::Error::Publisher  # Failed to publish a model operation
Promiscuous::Error::Subscriber # Failed to processing a message
Promiscuous::Error::Recover    # Deadlock recovery, Skipped messages
```

More details of their internals are in the code, but most messages will make sense.
Exceptions are logged as well.

Monitoring
----------

Promiscuous only supports NewRelic for the moment.
To install it, add the `promiscuous-newrelic` gem to your Gemfile:

```ruby
gem "promiscuous-newrelic"
```

For NewRelic error support, hook the `error_notifier`:

```ruby
Promiscuous.configure do |config|
  config.error_notifier = proc do |exception|
    NewRelic::Agent.notice_error(exception)
  end
end
```

For Airbrake support, hook the `error_notifier`:

```ruby
Promiscuous.configure do |config|
  config.error_notifier = proc do |exception|
    Airbrake.notify(exception)
  end
end
```

Monitor closely the size of the RabbitMQ queues (ready messages).

Managing Deploys
----------------

When adding new attributes on the publisher and subscriber sides,
you must deploy the publisher first, then the subscriber.
Doing otherwise may block the subscriber as it wouldn't be able to process
a message with missing attributes. In this case, you would have to
rollback the subscriber deployment, restart the worker, wait until fresh
messages are getting in, and re-deploy the subscriber.


Setup with Unicorn, Resque, etc.
--------------------------------

When unicorn or resqeue forks (booh!), you need to disconnect/reconnect
Promiscuous to ensure each child has its own connection.

Example with Unicorn:

```ruby
before_fork do
  Promiscuous.disconnect
end

after_fork do
  Promiscuous.connect
end
```

Example with Resque:

`lib/tasks/resque.rb`:
```ruby
require "resque/tasks"
task "resque:setup" => :environment do
  Resque.before_first_fork = proc do
    Promiscuous.disconnect
    Rails.logger.auto_flushing = 1
  end

  Resque.after_fork = proc do
    Promiscuous.connect
  end
end
```

Miscellaneous
=============

---

Roadmap
-------

* Make Promiscuous scale (processing 100,000 message a minute?)
* Central dashboard with Latency measurements, instrumentation,
* Query dependency optimizer
* Better synchronization tools and monitoring.
* Server Side Event hooks to provide near real time data to browsers.
* Helpers to refresh caches in the system

Coding Restrictions
-------------------

When using Promiscuous, multi updates and delete anymore are no longer possible
on the publisher side. Promiscuous enforces this rule with Mongoid but not yet with
ActiveRecord.

In the system, only one application can publish to a given endpoint. We call
this application the owner of corresponding model.

The subscribed models' callbacks should be idempotent as Promiscuous may
retry to process a message when a failure has occurred.

Limitations
-----------

1. ActiveRecord publishing support is limited. There is no support for
   transactions (which is a big problem), and there is no no safety net when
   doing multi updates / multi deletes.

2. Promiscuous doesn't scale yet: The current status of promiscuous is to
   enforce a total ordering of the model operations, which doesn't scale well
   on the subscriber side. We are working on the problem to allow parallel
   processing.

3. Publishing the same model to different endpoint (for API versioning) is not
   yet supported.

4. Subscribing the same model from different publishers is not yet supported.

License
-------

Promiscuous is distributed under the MIT license.
