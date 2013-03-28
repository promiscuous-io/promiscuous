require 'spec_helper'

describe Promiscuous do
  before { use_real_backend }
  before { load_models }
  before { record_callbacks(SubscriberModel) }

  context 'when some time passes' do
    before do
      class Promiscuous::Subscriber::Worker::MessageSynchronizer
        remove_const :CLEANUP_INTERVAL
        CLEANUP_INTERVAL = 1
        remove_const :QUEUE_MAX_AGE
        QUEUE_MAX_AGE = 1
      end
    end

    after do
      class Promiscuous::Subscriber::Worker::MessageSynchronizer
        remove_const :CLEANUP_INTERVAL
        CLEANUP_INTERVAL = 100
        remove_const :QUEUE_MAX_AGE
        QUEUE_MAX_AGE = 100
      end
    end

    before { run_subscriber_worker! }

    it 'unsubscribe to idle queues' do
      Promiscuous.context do
        5.times { PublisherModel.create }
      end

      eventually do
        SubscriberModel.num_saves.should == 5
        Celluloid::Actor[:message_synchronizer].subscriptions.size.should == 1
      end
    end
  end
end
