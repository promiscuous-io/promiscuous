require 'spec_helper'

describe Promiscuous do
  before { load_models; load_ephemerals }
  before { use_real_backend }
  before { run_subscriber_worker! }

  context 'when creating' do
    context 'with save' do
      it 'replicates' do
        pub = nil
        Promiscuous.context do
          pub = ModelEphemeral.new(:field_1 => '1', :field_2 => '2', :field_3 => '3')
          pub.save
        end

        eventually do
          sub = SubscriberModel.first
          sub.field_1.should == pub.field_1
          sub.field_2.should == pub.field_2
          sub.field_3.should == pub.field_3
        end
      end
    end

    context 'with create' do
      it 'replicates' do
        pub = nil
        Promiscuous.context do
          pub = ModelEphemeral.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')
        end

        eventually do
          sub = SubscriberModel.first
          sub.field_1.should == pub.field_1
          sub.field_2.should == pub.field_2
          sub.field_3.should == pub.field_3
        end
      end
    end
  end
end
