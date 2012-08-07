require 'spec_helper'
require 'integration/models'
require 'replicable/worker'

describe Replicable::Worker, '.subscribe' do
  before { use_fake_amqp(:app => 'test_subscriber') }

  before do
    define_constant(:subscriber, Replicable::Subscriber) do
      subscribe :model => SubscriberModel, :from => 'crowdtap/publisher_model'

      def replicate(payload)
        instance.field_1 = payload[:field_1]
        instance.field_2 = payload[:field_2]
        instance.field_3 = payload[:field_3]
      end
    end
  end

  before { Replicable::Worker.run }

  it 'subscribes to the correct queue' do
    queue_name = 'test_subscriber.replicable'
    Replicable::AMQP.subscribe_options[:queue_name].should == queue_name
  end

  after do
    Replicable::Subscriber.subscriptions.clear
  end
end
