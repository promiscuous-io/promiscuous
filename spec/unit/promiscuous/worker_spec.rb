require 'spec_helper'
require 'promiscuous/worker'

describe Promiscuous::Worker, '.subscribe' do
  before { load_models }
  before { use_fake_amqp(:app => 'test_subscriber') }

  before do
    define_constant('Subscriber', Promiscuous::Subscriber::Mongoid) do
      subscribe :from => 'crowdtap/publisher_model',
                :class => SubscriberModel

      def replicate(payload)
        instance.field_1 = payload[:field_1]
        instance.field_2 = payload[:field_2]
        instance.field_3 = payload[:field_3]
      end
    end
  end

  before { Promiscuous::Worker.replicate }

  it 'subscribes to the correct queue' do
    queue_name = 'test_subscriber.promiscuous'
    Promiscuous::AMQP.subscribe_options[:queue_name].should == queue_name
  end

  after do
    Promiscuous::Subscriber::AMQP.subscribers.clear
  end
end
