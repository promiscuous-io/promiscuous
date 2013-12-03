require 'spec_helper'

describe Promiscuous do
  before { load_models }
  before { use_real_backend { |config| config.logger.level = Logger::FATAL } }
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
      Promiscuous.context do
        PublisherModel.create(:field_1 => 'value')
      end
    end

    it "retries when an exception is raised" do
      sleep 1

      SubscriberModel.count.should == 0

      $raise = false

      eventually(:timeout => 2.seconds) do
        SubscriberModel.count.should == 1
      end
    end
  end
end
