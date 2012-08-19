require 'spec_helper'
require 'promiscuous/worker'

describe Promiscuous do
  before { load_models }

  before do
    define_constant('Publisher', ORM::PublisherBase) do
      publish :to => 'crowdtap/publisher_model',
              :class => :PublisherModel,
              :attributes => [:field_1, :field_2, :field_3]
    end

    define_constant('Subscriber', ORM::SubscriberBase) do
      subscribe :from => 'crowdtap/publisher_model',
                :class => SubscriberModel,
                :attributes => [:field_1, :field_2, :field_3]
    end
  end

  context 'when updating' do
    it 'replicates' do
      use_null_amqp
      pub = PublisherModel.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')
      use_real_amqp(:logger_level => Logger::FATAL)

      Promiscuous::Worker.replicate

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
      use_null_amqp(:logger_level => Logger::FATAL)
      pub1 = PublisherModel.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')
      use_real_amqp(:logger_level => Logger::FATAL)

      Promiscuous::Worker.replicate

      pub2 = PublisherModel.create(:field_1 => 'a', :field_2 => 'b', :field_3 => 'c')
      pub1.destroy

      eventually do
        SubscriberModel.where(ORM::ID => pub1.id).count.should == 0
        SubscriberModel.where(ORM::ID => pub2.id).count.should == 1
      end
    end
  end

  after do
    Promiscuous::AMQP.disconnect
    Promiscuous::Subscriber.subscribers.clear
  end
end
