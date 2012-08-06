require 'spec_helper'
require 'support/models'
require 'replicable/worker'

describe Replicable do
  before { use_real_amqp }

  before do
    define_constant(:publisher, Replicable::Publisher) do
      publish :model => PublisherModel, :to => 'crowdtap/publisher_model'

      def payload
        fields = {
          :field_1 => instance.field_1,
          :field_2 => instance.field_2,
          :field_3 => instance.field_3
        }
        if instance.respond_to?(:child_field_1)
          fields.merge!(:child_field_1 => instance.child_field_1)
        end
        fields
      end
    end

    define_constant(:subscriber, Replicable::Subscriber) do
      subscribe :from => 'crowdtap/publisher_model',
                :models => {'PublisherModel'      => SubscriberModel,
                            'PublisherModelChild' => SubscriberModelChild },
                :fields => [:field_1, :field_2, :field_3, :child_field_1?]
    end
  end

  before { Replicable::Worker.run }

  context 'when creating' do
    it 'replicates the parent' do
      pub = PublisherModel.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')

      eventually do
        sub = SubscriberModel.find(pub.id)
        sub.id.should == pub.id
        sub.field_1.should == pub.field_1
        sub.field_2.should == pub.field_2
        sub.field_3.should == pub.field_3
      end
    end

    it 'replicates the child' do
      pub = PublisherModelChild.create(:field_1 => '1', :field_2 => '2', :field_3 => '3',
                                       :child_field_1 => 'child_1')

      eventually do
        sub = SubscriberModelChild.find(pub.id)
        sub.id.should == pub.id
        sub.field_1.should == pub.field_1
        sub.field_2.should == pub.field_2
        sub.field_3.should == pub.field_3
        sub.child_field_1.should == pub.child_field_1
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
