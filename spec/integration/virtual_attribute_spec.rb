require 'spec_helper'

describe Promiscuous do
  before { use_real_backend }
  before { load_models }
  before { run_subscriber_worker! }

  context 'when publishing and subscribing to a virtual attribute derived from a published attribute' do
    before do
      PublisherModel.class_eval do
        publish :field_1_derived

        def field_1_derived
          field_1 + 'derivied'
        end
      end

      SubscriberModel.class_eval do
        subscribe :field_1_derived
      end
    end

    context 'when creating' do
      it 'replicates' do
        pub = PublisherModel.create(:field_1 => '1')

        eventually do
          sub = SubscriberModel.first
          sub.field_1_derived.should == pub.field_1_derived
        end
      end
    end

    context 'when updating' do
      it 'replicates' do
        pub = PublisherModel.create(:field_1 => '1')
        pub.update_attributes(:field_1 => '1_updated')

        eventually do
          sub = SubscriberModel.first
          sub.field_1_derived.should == pub.field_1_derived
        end
      end
    end
  end

  context 'when publishing and subscribing to a virtual attribute derived from a non-published attribute' do
    before do
      PublisherModel.class_eval do
        publish :field_1_derived

        def field_1_derived
          unpublished + 'derivied'
        end
      end

      SubscriberModel.class_eval do
        subscribe :field_1_derived
      end
    end

    context 'when creating' do
      it 'replicates' do
        pub = PublisherModel.create(:unpublished => '1')

        eventually do
          sub = SubscriberModel.first
          sub.field_1_derived.should == pub.field_1_derived
        end
      end
    end

    context 'when updating' do
      it 'only replicates the create' do
        pub = PublisherModel.create(:unpublished => '1')
        derived_field = pub.field_1_derived

        sub = nil
        eventually do
          sub = SubscriberModel.first
          sub.field_1_derived.should == derived_field
        end

        pub.update_attributes(:unpublished => '1_updated')

        sleep 0.1

        sub.field_1_derived.should == derived_field
      end
    end
  end

  context 'when publishing and subscribing to a virtual attribute derived from a non-published attribute with a dependency declared' do
    before do
      PublisherModel.class_eval do
        publish :field_1_derived, :use => :unpublished

        def field_1_derived
          unpublished + 'derivied'
        end
      end

      SubscriberModel.class_eval do
        subscribe :field_1_derived
      end
    end

    context 'when updating' do
      it 'replicates the create and update' do
        pub = PublisherModel.create(:unpublished => '1')
        derived_field = pub.field_1_derived

        sub = nil
        eventually do
          sub = SubscriberModel.first
          sub.field_1_derived.should == derived_field
        end

        pub.update_attributes(:unpublished => '1_updated')

        sleep 0.1

        sub.field_1_derived.should == derived_field
      end
    end
  end
end
