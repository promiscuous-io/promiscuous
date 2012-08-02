require 'spec_helper'
require 'replicable/subscriber/worker'

describe Replicable::Subscriber::Worker, '.subscribe' do
  before { use_fake_amqp(:app => 'sniper') }

  before do
    define_constant(:associated_model) do
      include Mongoid::Document

      has_many :subscriber_models
    end

    define_constant(:subscriber_model) do
      include Mongoid::Document
      include Replicable::Subscriber

      field :field_1
      field :field_2
      field :field_3

      replicate :from => 'crowdtap', :class_name => 'publisher_model' do
        field :field_1
        field :field_2
        field :field_3
        belongs_to :associated_model
      end
    end
    Replicable::Subscriber::Worker.run
  end

  it 'subscribes to the correct queue' do
    queue_name = 'sniper.replicable'
    Replicable::AMQP.subscribe_options[:queue_name].should == queue_name
  end

  it 'creates all the correct bindings' do
    bindings = [ "crowdtap.#.publisher_model.#.*" ]
    Replicable::AMQP.subscribe_options[:bindings].should =~ bindings
  end

  it 'binds to all the fields, including associations' do
    SubscriberModel.replicate_options[:fields].should =~ [:field_1, :field_2, :field_3, :associated_model_id]
  end

  after do
    Replicable::Subscriber.subscriptions.clear
  end
end
