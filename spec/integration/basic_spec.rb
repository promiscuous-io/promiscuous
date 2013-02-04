require 'spec_helper'

describe Promiscuous do
  before { load_models }
  before { use_real_backend }

  before do
    define_constant('Publisher', ORM::PublisherBase) do
      publish :to => 'crowdtap/publisher_model',
              :class => :PublisherModel,
              :attributes => [:field_1, :field_2, :field_3]
    end

    define_constant('Subscriber', ORM::SubscriberBase) do
      subscribe :from => 'crowdtap/publisher_model',
                :class => :SubscriberModel,
                :attributes => [:field_1, :field_2, :field_3]
    end
  end

  before { run_subscriber_worker! }

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

    if ORM.has(:find_and_modify)
      it 'replicate' do
        pub = PublisherModel.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')
        PublisherModel.find_and_modify('$set' => { :field_1 => '1_updated', :field_2 => '2_updated'})
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
      pub = PublisherModel.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')

      eventually { SubscriberModel.count.should == 1 }
      pub.destroy
      eventually { SubscriberModel.count.should == 0 }
    end
  end
end
