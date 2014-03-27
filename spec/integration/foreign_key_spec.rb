require 'spec_helper'

describe Promiscuous do
  before { load_models }
  before { use_real_backend }

  before { SubscriberModel.class_eval { subscribe :foreign_key => :publisher_id } }

  before { run_subscriber_worker! }

  context 'when creating' do
    it 'replicates' do
      pub_id = ORM.generate_id
      pub = PublisherModel.new(:field_1 => '1', :field_2 => '2', :field_3 => '3')
      pub.id = pub_id
      pub.save

      eventually do
        sub = SubscriberModel.first
        sub.publisher_id.should == pub.id
        sub.field_1.should == pub.field_1
        sub.field_2.should == pub.field_2
        sub.field_3.should == pub.field_3
      end
    end
  end

  context 'when updating' do
    it 'replicates' do
      pub_id = ORM.generate_id
      pub = PublisherModel.new(:field_1 => '1', :field_2 => '2', :field_3 => '3')
      pub.id = pub_id
      pub.save
      pub.update_attributes(:field_1 => '1_updated', :field_2 => '2_updated')

      eventually do
        sub = SubscriberModel.first
        sub.publisher_id.should == pub.id
        sub.field_1.should == pub.field_1
        sub.field_2.should == pub.field_2
        sub.field_3.should == pub.field_3
      end
    end
  end

  context 'when updating (upsert)' do
    it 'replicates' do
      pub_id = ORM.generate_id
      pub = PublisherModel.new(:field_1 => '1', :field_2 => '2', :field_3 => '3')
      pub.id = pub_id
      pub.save

      eventually { SubscriberModel.first.should_not == nil }

      SubscriberModel.first.destroy
      #Promiscuous::Config.logger.level = Logger::FATAL

      # Promiscuous.context do
        # pub.update_attributes(:field_1 => '1_updated', :field_2 => '2_updated')
      # end

      # eventually do
        # sub = SubscriberModel.first
        # sub.publisher_id.should == pub.id
        # sub.field_1.should == pub.field_1
        # sub.field_2.should == pub.field_2
        # sub.field_3.should == pub.field_3
      # end
    end
  end

  context 'when destroying' do
    it 'replicates' do
      pub_id = ORM.generate_id
      pub = PublisherModel.new(:field_1 => '1', :field_2 => '2', :field_3 => '3')
      pub.id = pub_id
      pub.save

      eventually { SubscriberModel.count.should == 1 }
      pub.destroy
      eventually { SubscriberModel.count.should == 0 }
    end
  end
end
