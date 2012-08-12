require 'spec_helper'
require 'promiscuous/worker'

describe Promiscuous do
  before { load_models }
  before { use_real_amqp }

  before do
    define_constant('Publisher', Promiscuous::Publisher::Mongoid) do
      publish :to => 'crowdtap/publisher_model',
              :class => PublisherModel,
              :attributes => [:field_1, :field_2, :field_3]
    end

    define_constant('Subscriber', Promiscuous::Subscriber::Mongoid) do
      subscribe :from => 'crowdtap/publisher_model',
                :class => SubscriberModel,
                :attributes => [:field_1, :field_2, :field_3]
    end
  end

  before { Promiscuous::Worker.replicate }

  context 'when creating' do
    context 'with new' do
      it 'replicates' do
        pub = PublisherModel.new(:field_1 => '1', :field_2 => '2', :field_3 => '3')
        pub.save

        eventually do
          sub = SubscriberModel.first
          sub.id.should == pub.id
          sub.field_1.should == pub.field_1
          sub.field_2.should == pub.field_2
          sub.field_3.should == pub.field_3
        end
      end
    end

    context 'with create' do
      it 'replicates' do
        pub = PublisherModel.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')

        eventually do
          sub = SubscriberModel.first
          sub.id.should == pub.id
          sub.field_1.should == pub.field_1
          sub.field_2.should == pub.field_2
          sub.field_3.should == pub.field_3
        end
      end
    end
  end

  context 'when updating' do
    it 'replicates' do
      pub = PublisherModel.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')
      pub.update_attributes(:field_1 => '1_updated', :field_2 => '2_updated')

      eventually do
        sub = SubscriberModel.first
        sub.id.should == pub.id
        sub.field_1.should == pub.field_1
        sub.field_2.should == pub.field_2
        sub.field_3.should == pub.field_3
      end
    end
  end

  context 'when destroying' do
    it 'replicates' do
      pub = PublisherModel.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')

      eventually { SubscriberModel.count.should == 1 }
      pub.destroy
      eventually { SubscriberModel.count.should == 0 }
    end
  end

  after do
    Promiscuous::AMQP.close
    Promiscuous::Subscriber.subscribers.clear
  end
end
