unless RUBY_PLATFORM == 'java' || ENV['TRAVIS']
  require 'simplecov'

  SimpleCov.start do
    add_filter '/spec/'
    add_filter 'debug.rb'

    add_group 'Controllers',  'lib/promiscuous'
    add_group 'AMQP Drivers', 'lib/promiscuous/amqp'
    add_group 'CLI',          'lib/promiscuous/cli'
    add_group 'Publisher',    'lib/promiscuous/publisher'
    add_group 'Subscriber',   'lib/promiscuous/subscriber'
  end
end
