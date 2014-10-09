require 'spec_helper'

describe Promiscuous do
  before { load_models }
  before { use_real_backend { |config| config.logger.level = Logger::FATAL
                                       config.error_ttl = ttl
                                       config.error_notifier = proc { $error = true } } }
  before { run_subscriber_worker! }
  before { $raise = true }

  context 'when raising a regular exception' do
    before do
      SubscriberModel.class_eval do
        before_save do
          raise 'something bad' if $raise
        end
      end
    end
    before do
      PublisherModel.create(:field_1 => 'value')
    end

    context 'when the ttl is shorter then the subscriber is expected to receive the message' do
      let(:ttl) { 10 }

      it "retries when an exception is raised and notifies" do
        sleep 1

        SubscriberModel.count.should == 0
        $error.should == true

        $raise = false

        eventually(:timeout => 5.seconds) do
          SubscriberModel.count.should == 1
        end
      end
    end

    context 'when the ttl is longer then the subscriber is expected to receive the message' do
      let(:ttl) { 99999 }

      it "doesn't retry when an exception is raised as its shorter then the ttl" do
        sleep 1

        SubscriberModel.count.should == 0
        $error.should == true

        $raise = false

        sleep 1

        SubscriberModel.count.should == 0
      end
    end
  end
end
