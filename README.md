Promiscuous
===========

[![Build Status](https://secure.travis-ci.org/crowdtap/promiscuous.png?branch=master)](https://secure.travis-ci.org/crowdtap/promiscuous)

Promiscuous is designed to facilitate designing a
[service-oriented architecture](http://en.wikipedia.org/wiki/Service-oriented_architecture)
in Ruby.

Promiscuous offers an automatic way of propagating your data across one or more
applications. It supports Mongoid2, Mongoid3 and ActiveRecord.
It relies on [RabbitMQ](http://www.rabbitmq.com/) to push data around.

Philosophy
----------

In order for a service-oriented system to be successful, services *must* be
loosely coupled.  The traditional Ruby way of tackling this problem is to
provide RESTful APIs.
Sadly, this come to a cost since one must write controllers, integration tests, etc.
Promiscuous to the rescue

Compatibility
-------------

Promiscuous is tested against MRI 1.9.2 and 1.9.3.

ActiveRecord, Mongoid 2.4.x and Mongoid 3.0.x are supported.

License
-------

Promiscuous is distributed under the MIT license.
