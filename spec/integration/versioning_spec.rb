require 'spec_helper'

if ORM.has(:versioning)
  describe Promiscuous do
    before { load_models }
    before { use_real_amqp }

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

    before { Promiscuous::Worker.replicate }

    context 'when creating' do
      it 'replicates without version' do
        pub = PublisherModel.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')
        eventually do
          sub = SubscriberModel.first
          sub.id.should == pub.id
          sub._psv.should == nil
        end
        pub.reload
        pub._psv.should == nil
      end
    end

    context 'when updating' do
      it "replicates until the subscriber's version is less than the publisher's one" do
        pub = PublisherModel.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')

        sub = nil
        eventually do
          sub = SubscriberModel.first
          sub.id.should == pub.id
        end

        # The subscriber will ignore the two first updates with a version set to 3
        sub._psv = 3
        sub.field_1 = 'sub'
        sub.save

        pub.update_attributes(:field_1 => 'pub1')
        eventually { sub.reload; sub.field_1.should == 'sub' }

        pub.update_attributes(:field_1 => 'pub2')
        eventually { sub.reload; sub.field_1.should == 'sub' }

        pub.update_attributes(:field_1 => 'pub3')
        eventually { sub.reload; sub.field_1.should == 'pub3' }

        pub.update_attributes(:field_1 => 'pub4')
        eventually { sub.reload; sub.field_1.should == 'pub4' }

        pub.update_attributes(:field_1 => 'pub5')
        eventually { sub.reload; sub.field_1.should == 'pub5' }
      end
    end
  end
end
