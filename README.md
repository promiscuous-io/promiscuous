Promiscuous [![Gem Version](https://badge.fury.io/rb/promiscuous.png)](http://rubygems.org/gems/promiscuous) [![Build Status](https://travis-ci.org/promiscuous-io/promiscuous.png?branch=master)](https://travis-ci.org/promiscuous-io/promiscuous)
==========

Promiscuous is a **pub-sub framework** for easily replicating data
across your Ruby applications. Promiscuous guarantees that a subscriber
never sees out of order updates and that all updates are eventually replicated.

**Benefits over database replication**

* Hetrogenous replication. e.g. replicate from Mongo -> Postgres | ElasticSearch
  | Redis ...
* "Remote observers". The ability to observe model changes in one application from another.
* Publish [virtual attributes](https://github.com/promiscuous-io/promiscuous/wiki/Features-and-Recipes#wiki-attributes)


Rails Quick Tutorial
--------------------

### 1. Preparation

We need to few things for the promiscuous tutorial:

* The AMQP broker [RabbitMQ](http://www.rabbitmq.com/) up and running.
* The key-value storage system [Redis](http://redis.io/) (at least 2.6) up and running.
* Two Rails applications with the promiscuous gem installed.
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

Note: With ActiveRecord on the publisher side, promiscuous only supports PostgreSQL at
the moment. You also need to change `max_prepared_transactions = 10` in the config of
PostgreSQL.

### 3. Subscribing

Similarly to the publisher app, we can subscribe to the attributes:

```ruby
# app/models/user.rb on the subscriber app
class User
  include Promiscuous::Subscriber
  subscribe :name, :email

  after_create { Rails.logger.info "Hi #{name}!" }
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
web admin page. Create a new user in the publisher's Rails console with:

```ruby
User.create(:name => 'Yoda')`
```

You should see the message "Hi Yoda!" appearing in the log file of the subscriber.

Promiscuous in Depth
--------------------

### Features and Recipes
* [Attributes](https://github.com/promiscuous-io/promiscuous/wiki/Features-and-Recipes#wiki-attributes)
* [Ephemerals & Observers](https://github.com/promiscuous-io/promiscuous/wiki/Features-and-Recipes#wiki-ephemerals-observers)
* [Polymorphism](https://github.com/promiscuous-io/promiscuous/wiki/Features-and-Recipes#wiki-polymorphism)
* [Embedded Documents](https://github.com/promiscuous-io/promiscuous/wiki/Features-and-Recipes#wiki-embedded-documents)
* [Foreign Keys](https://github.com/promiscuous-io/promiscuous/wiki/Features-and-Recipes#wiki-foreign-keys)
* [Namespace Mapping](https://github.com/promiscuous-io/promiscuous/wiki/Features-and-Recipes#wiki-namespace-mapping)
* [Promiscuous DSL](https://github.com/promiscuous-io/promiscuous/wiki/Features-and-Recipes#wiki-promiscuous-dsl)

### Configuration
* [Configuration Options](https://github.com/promiscuous-io/promiscuous/wiki/Configuration#wiki-configuration-options)
* [Subscriber CLI Options](https://github.com/promiscuous-io/promiscuous/wiki/Configuration#wiki-subscriber-cli-options)

### Testing
* [Exporting Publishers Definitions](https://github.com/promiscuous-io/promiscuous/wiki/Testing#wiki-exporting-publishers-definitions)
* [Unit Testing](https://github.com/promiscuous-io/promiscuous/wiki/Testing#wiki-unit-testing)
* [Integration Testing](https://github.com/promiscuous-io/promiscuous/wiki/Testing#wiki-integration-testing)
* [Gemify your Apps](https://github.com/promiscuous-io/promiscuous/wiki/Testing#wiki-gemify-your-apps)

### Going to Production
* [RabbitMQ & Redis](https://github.com/promiscuous-io/promiscuous/wiki/Going-to-Production#wiki-rabbitmq-and-redis)
* [Initial Sync](https://github.com/promiscuous-io/promiscuous/wiki/Going-to-Production#wiki-initial-sync)
* [Error Handling](https://github.com/promiscuous-io/promiscuous/wiki/Going-to-Production#wiki-error-handling)
* [Instrumentation](https://github.com/promiscuous-io/promiscuous/wiki/Going-to-Production#wiki-instrumentation)
* [Managing Deploys](https://github.com/promiscuous-io/promiscuous/wiki/Going-to-Production#wiki-managing-deploys)
* [Setup with Unicorn, Resque, etc.](https://github.com/promiscuous-io/promiscuous/wiki/Going-to-Production#wiki-setup-with-unicorn-resque-etc)

### Miscellaneous
* [Roadmap](https://github.com/promiscuous-io/promiscuous/wiki/Miscellaneous#wiki-roadmap)
* [Coding Restrictions](https://github.com/promiscuous-io/promiscuous/wiki/Miscellaneous#wiki-coding-restrictions)
* [Limitations](https://github.com/promiscuous-io/promiscuous/wiki/Miscellaneous#wiki-limitations)
* [FAQs](https://github.com/promiscuous-io/promiscuous/wiki/Miscellaneous#wiki-faqs)
* [License](https://github.com/promiscuous-io/promiscuous/wiki/Miscellaneous#wiki-license)
