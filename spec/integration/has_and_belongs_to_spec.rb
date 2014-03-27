require 'spec_helper'

describe Promiscuous, 'belongs_to relationships' do
  before { use_real_backend }
  before { load_models }
  before { run_subscriber_worker! }

  context 'when creating' do
    it 'replicates' do
      publisher_model = PublisherModel.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')
      pub = PublisherModelBelongsTo.create(:publisher_model => publisher_model)
      pub.reload

      eventually do
        sub = SubscriberModelBelongsTo.first
        sub.id.should == pub.id
        sub.publisher_model_id.should == pub.publisher_model_id
      end
    end
  end

  context 'when updating' do
    it 'replicates' do
      publisher_model_1 = PublisherModel.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')
      publisher_model_2 = PublisherModel.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')
      pub = PublisherModelBelongsTo.create(:publisher_model => publisher_model_1)
      pub.update_attributes(:publisher_model => publisher_model_2)
      pub.reload

      eventually do
        sub = SubscriberModelBelongsTo.first
        sub.id.should == pub.id
        sub.publisher_model_id.should == pub.publisher_model_id
      end
    end
  end
end
