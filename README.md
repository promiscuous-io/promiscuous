<p align="center">
  <a href="https://github.com/crowdtap/promiscuous/#introduction">
    <img src="https://github.com/crowdtap/promiscuous/wiki/promiscuous.png">
  </a>
</p>

[![Build Status](https://travis-ci.org/crowdtap/promiscuous.png?branch=travis)](https://travis-ci.org/crowdtap/promiscuous)

Introduction
------------

Promiscuous is a **publisher-subscriber framework** for easily replicating data
across your Ruby applications.

**Motivation**

> If you hit the Amazon.com gateway page, the application calls more than 100
> services to collect data and construct the page for you.

— _Werner Vogels, CTO, Amazon.com, 2006_

When it comes to scaling a team, having just one codebase adversely impacts productivity
and performance.  A more sustainable approach is to adopt a [service-oriented
architecture](http://en.wikipedia.org/wiki/Service-oriented_architecture) (SOA),
with a system composed of several *loosely coupled* applications, each existing in isolation
with its own database.  In this manner, each service can be tested separately,
deployed separately and even owned separately by developers.  Unfortunately, it
has not always been easy to achieve this with Ruby.

Promiscuous facilitates designing Ruby based SOA services. It does this by
watching models in publisher applications and sending corresponding model operations
on a common message bus powered by [RabbitMQ](http://www.rabbitmq.com/).
Each subscriber has its own queue to receive messages asynchronously.

**Role in our Infrastructure**

At Crowdtap, we use Promiscuous as the central tier of our system.  It
replicates a subset of our core models backed by [MongoDB](http://www.mongodb.org/) to
internal services, such as our e-commerce store on
[PostgreSQL](http://www.postgresql.org/) and our analytics engine on
[ElasticSearch](www.elasticsearch.org).

**Difference from traditional replication**

By using [Redis](http://redis.io) to synchronize and order operations,
Promiscuous guarantees that a subscriber never sees out of order updates,
even when using shards. This guarantee considerably reduces the complexity of
an application, while improving its robustness.

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

Promiscuous in Depth
--------------------

### Features and Recipes
* [Attributes](https://github.com/crowdtap/promiscuous/wiki/Features-and-Recipes#wiki-attributes)
* [Ephemerals & Observers](https://github.com/crowdtap/promiscuous/wiki/Features-and-Recipes#wiki-ephemerals-observers)
* [Polymorphism](https://github.com/crowdtap/promiscuous/wiki/Features-and-Recipes#wiki-polymorphism)
* [Embedded Documents](https://github.com/crowdtap/promiscuous/wiki/Features-and-Recipes#wiki-embedded-documents)
* [Foreign Keys](https://github.com/crowdtap/promiscuous/wiki/Features-and-Recipes#wiki-foreign-keys)
* [Namespace Mapping](https://github.com/crowdtap/promiscuous/wiki/Features-and-Recipes#wiki-namespace-mapping)
* [Promiscuous DSL](https://github.com/crowdtap/promiscuous/wiki/Features-and-Recipes#wiki-promiscuous-dsl)

### The Replication Mechanism
* [Pipeline Description](https://github.com/crowdtap/promiscuous/wiki/The-Replication-Mechanism#wiki-pipeline-description)

### Configuration
* [Configuration Options](https://github.com/crowdtap/promiscuous/wiki/Configuration#wiki-configuration-options)
* [Subscriber CLI Options](https://github.com/crowdtap/promiscuous/wiki/Configuration#wiki-subscriber-cli-options)

### Testing
* [Exporting Publishers Definitions](https://github.com/crowdtap/promiscuous/wiki/Testing#wiki-exporting-publishers-definitions)
* [Unit Testing](https://github.com/crowdtap/promiscuous/wiki/Testing#wiki-unit-testing)
* [Integration Testing](https://github.com/crowdtap/promiscuous/wiki/Testing#wiki-integration-testing)
* [Gemify your Apps](https://github.com/crowdtap/promiscuous/wiki/Testing#wiki-gemify-your-apps)

### Going to Production
* [RabbitMQ & Redis](https://github.com/crowdtap/promiscuous/wiki/Going-to-Production#wiki-rabbitmq-and-redis)
* [Initial Sync](https://github.com/crowdtap/promiscuous/wiki/Going-to-Production#wiki-initial-sync)
* [Error Handling](https://github.com/crowdtap/promiscuous/wiki/Going-to-Production#wiki-error-handling)
* [Instrumentation](https://github.com/crowdtap/promiscuous/wiki/Going-to-Production#wiki-instrumentation)
* [Managing Deploys](https://github.com/crowdtap/promiscuous/wiki/Going-to-Production#wiki-managing-deploys)
* [Setup with Unicorn, Resque, etc.](https://github.com/crowdtap/promiscuous/wiki/Going-to-Production#wiki-setup-with-unicorn-resque-etc)

### Miscellaneous
* [Roadmap](https://github.com/crowdtap/promiscuous/wiki/Miscellaneous#wiki-roadmap)
* [Coding Restrictions](https://github.com/crowdtap/promiscuous/wiki/Miscellaneous#wiki-coding-restrictions)
* [Limitations](https://github.com/crowdtap/promiscuous/wiki/Miscellaneous#wiki-limitations)
* [FAQs](https://github.com/crowdtap/promiscuous/wiki/Miscellaneous#wiki-faqs)
* [License](https://github.com/crowdtap/promiscuous/wiki/Miscellaneous#wiki-license)
