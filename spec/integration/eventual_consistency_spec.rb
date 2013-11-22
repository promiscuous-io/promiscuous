require 'spec_helper'

describe Promiscuous do
  before { use_real_backend }
  before { load_models }
  before { run_subscriber_worker! }
  before { Promiscuous::Config.consistency = consistency }

  context 'when a messages are processed out of order' do
    before do
      pub = nil
      Promiscuous.context do
        pub = PublisherModel.create(:field_1 => '1')
        pub.update_attributes(:field_1 => '2')
      end

      eventually { SubscriberModel.count.should == 1 }

      postpone_messages { Promiscuous.context { pub.update_attributes(:field_1 => '3') } }
      Promiscuous.context { pub.update_attributes(:field_1 => '4') }
      sleep 1
      process_postponed_messages
      sleep 1
    end

    context 'when consistency is none' do
      let(:consistency) { :none }

      it 'subscribes to messages out of order' do
        SubscriberModel.first.field_1.should == '3'
      end
    end

    context 'when consistency is eventual' do
      let(:consistency) { :eventual }

      it 'subscribes to messages in the correct order (by dropping the last message)' do
        eventually { SubscriberModel.first.field_1.should == '4' }
      end
    end

    context 'when consistency is causal' do
      let(:consistency) { :causal }

      it 'subscribes to messages in the correct order (by waiting for lost message)' do
        eventually { SubscriberModel.first.field_1.should == '4' }
      end
    end
  end

  context 'when a message arrives out of order' do
    before do
      pub = nil
      Promiscuous.context do
        pub = PublisherModel.create(:field_1 => '1')
        pub.update_attributes(:field_1 => '2')
      end

      eventually { SubscriberModel.count.should == 1 }

      postpone_and_ack_messages do
        Promiscuous.context { pub.update_attributes(:field_1 => '3') }
      end
      Promiscuous.context { pub.update_attributes(:field_1 => '4') }
    end

    context 'when consistency is none' do
      let(:consistency) { :none }

      it 'blocks waiting for the missing message' do
        eventually { SubscriberModel.first.field_1.should == '4' }
      end
    end

    context 'when consistency is eventual' do
      let(:consistency) { :eventual }

      it 'replicates when there are missing messages' do
        eventually do
          SubscriberModel.first.field_1.should == '4'
        end
      end
    end

    context 'when consistency is causal' do
      let(:consistency) { :causal }

      it 'blocks waiting for the missing message' do
        eventually { SubscriberModel.first.field_1.should == '2' }
      end
    end
  end
end
