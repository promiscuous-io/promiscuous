require 'spec_helper'
require 'replicable/subscriber/worker'

describe Replicable::Subscriber::Worker, '.subscribe' do
  before { Replicable::AMQP.configure(:backend => :fake, :app => 'sniper') }

  before do
    define_constant(:subscriber_model) do
      include Mongoid::Document
      include Replicable::Subscriber

      field :field_1
      field :field_2
      field :field_3

      replicate :from => 'crowdtap',
                :class_name => 'publisher_model',
                :fields => [:field_1, :field_2, :field_3]
    end
    Replicable::Subscriber::Worker.run
  end

  it 'subscribes to the correct queue' do
    queue_name = 'sniper.replicable'
    Replicable::AMQP.subscribe_options[:queue_name].should == queue_name
  end

  it 'creates all the correct bindings' do
    bindings = [
      "crowdtap.#.publisher_model.#.create.$fields$.#",
      "crowdtap.#.publisher_model.#.destroy.$fields$.#",
      "crowdtap.#.publisher_model.#.update.$fields$.#.field_1.#",
      "crowdtap.#.publisher_model.#.update.$fields$.#.field_2.#",
      "crowdtap.#.publisher_model.#.update.$fields$.#.field_3.#"
    ]
    Replicable::AMQP.subscribe_options[:bindings].should =~ bindings
  end

  after do
    Replicable::Subscriber.subscriptions.clear
  end
end
