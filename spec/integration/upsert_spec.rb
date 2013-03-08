require 'spec_helper'

describe Promiscuous do
  before { load_models }
  before { use_real_backend(:logger_level => Logger::FATAL) }
  before { run_subscriber_worker! }

  context 'when updating' do
    it 'replicates' do
      pub = nil
      Promiscuous.context do
        pub_id = ORM.generate_id
        pub = PublisherModel.new(:field_1 => '1', :field_2 => '2', :field_3 => '3')
        pub.id = pub_id
        pub.save
      end

      eventually { SubscriberModel.first.should_not == nil }

      SubscriberModel.first.destroy
      Promiscuous.context do
        pub.update_attributes(:field_1 => '1_updated', :field_2 => '2_updated')
      end

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
      pub1 = pub2 = nil
      Promiscuous.context do
        pub1 = PublisherModel.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')
      end
      eventually { SubscriberModel.first.should_not == nil }

      SubscriberModel.first.destroy

      Promiscuous.context { pub1.destroy }
      Promiscuous.context { pub2 = PublisherModel.create }

      eventually do
        SubscriberModel.where(ORM::ID => pub1.id).count.should == 0
        SubscriberModel.where(ORM::ID => pub2.id).count.should == 1
      end
    end
  end
end
