require 'spec_helper'
require 'support/models'
require 'replicable/worker'

describe Replicable do
  before { use_real_amqp }

  before do
    define_constant(:publisher, Replicable::Publisher) do
      publish :model => PublisherModel, :to => 'crowdtap/publisher_model'

      def payload
        {
          :field_1 => instance.field_1,
          :field_2 => instance.field_2,
          :field_3 => instance.field_3
        }
      end
    end

    define_constant(:subscriber, Replicable::Subscriber) do
      subscribe :from => 'crowdtap/publisher_model'

      def model
        case type
        when 'PublisherModel'
          SubscriberModel
        when 'PublisherModelChild'
          SubscriberModelChild
        end
      end

      def replicate(payload)
        instance.field_1 = payload[:field_1]
        instance.field_2 = payload[:field_2]
        instance.field_3 = payload[:field_3]
      end
    end
  end

  before { Replicable::Worker.run }

  context 'when creating' do
    it 'replicates' do
      pub = PublisherModelChild.create(:field_1 => '1', :field_2 => '2', :field_3 => '3',
                                       :child_field_1 => 'child_1')

      eventually do
        sub = SubscriberModel.first
        sub.id.should == pub.id
        sub.field_1.should == pub.field_1
        sub.field_2.should == pub.field_2
        sub.field_3.should == pub.field_3
        sub.child_field_1 == pub.child_field_1
      end

    end
  end

  after do
    Replicable::AMQP.close
    Replicable::Subscriber.subscriptions.clear
  end
end

# 1. Nothing
# 2. Same behavior as the parent
