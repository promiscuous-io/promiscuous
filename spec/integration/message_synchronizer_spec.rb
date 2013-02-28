require 'spec_helper'

describe Promiscuous do
  before { use_real_backend }
  before { load_models }
  before { record_callbacks(SubscriberModel) }

  context 'when some time passes' do
    before do
      class Promiscuous::Subscriber::Worker::MessageSynchronizer
        remove_const :CLEANUP_INTERVAL
        remove_const :QUEUE_MAX_AGE
        CLEANUP_INTERVAL = 0.1
        QUEUE_MAX_AGE = 0.1
      end
    end

    after do
      class Promiscuous::Subscriber::Worker::MessageSynchronizer
        remove_const :CLEANUP_INTERVAL
        remove_const :QUEUE_MAX_AGE
        CLEANUP_INTERVAL = 1.minute
        QUEUE_MAX_AGE = 10.minutes
      end
    end

    before { run_subscriber_worker! }

    it 'unsubscribe to idle queues' do
      Promiscuous.transaction { PublisherModel.create }

      eventually do
        SubscriberModel.num_saves.should == 1
        Celluloid::Actor[:message_synchronizer].subscriptions.should be_blank
      end
    end
  end
end
