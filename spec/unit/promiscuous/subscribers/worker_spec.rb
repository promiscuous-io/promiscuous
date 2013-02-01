require 'spec_helper'

describe Promiscuous::Subscriber::Worker, '.subscribe' do
  before { load_models }
  before { use_null_amqp(:app => 'test_subscriber') }

  before do
    define_constant('Subscriber', ORM::SubscriberBase) do
      subscribe :from => 'crowdtap/publisher_model',
                :class => SubscriberModel

      def replicate(payload)
        instance.field_1 = payload[:field_1]
        instance.field_2 = payload[:field_2]
        instance.field_3 = payload[:field_3]
      end
    end
  end

  let(:sub_worker) { Promiscuous::Subscriber::Worker.new }

  it 'subscribes to the correct queue' do
    queue_name = 'test_subscriber.promiscuous.new'
    sub_worker.pump.queue_bindings[:queue_name].should == queue_name
  end
end
