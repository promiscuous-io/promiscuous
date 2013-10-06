require 'spec_helper'

describe Promiscuous do
  before { use_real_backend }
  before { load_models }
  before { run_subscriber_worker! }

  context 'when creating' do
    context 'with new' do
      it 'replicates' do
        pub = Promiscuous.context do
          pub = PublisherModel.new(:field_1 => '1', :field_2 => '2', :field_3 => '3')
          pub.save
          pub
        end
        pub.reload

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
        pub = Promiscuous.context do
          PublisherModel.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')
        end
        pub.reload

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
      pub = nil
      Promiscuous.context do
        pub = PublisherModel.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')
        pub.update_attributes(:field_1 => '1_updated', :field_2 => '2_updated')
      end
      pub.reload

      eventually do
        sub = SubscriberModel.first
        sub.id.should == pub.id
        sub.field_1.should == pub.field_1
        sub.field_2.should == pub.field_2
        sub.field_3.should == pub.field_3
      end
    end

    if ORM.has(:find_and_modify)
      it 'replicate' do
        pub = nil
        Promiscuous.context do
          pub = PublisherModel.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')
          PublisherModel.find_and_modify({'$set' => { :field_1 => '1_updated', :field_2 => '2_updated'}}, :new => true)
        end
        pub.reload

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

  context 'when destroying' do
    it 'replicates' do
      pub = Promiscuous.context do
        PublisherModel.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')
      end

      eventually { SubscriberModel.count.should == 1 }
      Promiscuous.context { pub.destroy }
      PublisherModel.count.should == 0
      eventually { SubscriberModel.count.should == 0 }
    end
  end
end
