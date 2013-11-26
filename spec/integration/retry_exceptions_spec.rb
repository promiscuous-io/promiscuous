require 'spec_helper'

describe Promiscuous do
  before { load_models }
  before { use_real_backend { |config| config.logger.level = Logger::FATAL } }
  before { run_subscriber_worker! }
  before { $raise = true }
  before { $exceptions = [] }
  before { Promiscuous::Config.error_notifier = proc { |e| $exceptions << e } }

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

    it "retries when an exception is raised but still notifies" do
      sleep 1

      SubscriberModel.count.should == 0

      $raise = false

      eventually(:timeout => 2.seconds) do
        SubscriberModel.count.should == 1
        $exceptions.should_not be_empty
      end
    end
  end

  context 'when raising a regular exception' do
    before do
      SubscriberModel.class_eval do
        before_save do
          raise Promiscuous::Error::Retry if $raise
        end
      end
    end
    before do
      Promiscuous.context do
        PublisherModel.create(:field_1 => 'value')
      end
    end

    it "retries when an exception is raised and isn't notifies" do
      sleep 1

      SubscriberModel.count.should == 0

      $raise = false

      eventually(:timeout => 2.seconds) do
        SubscriberModel.count.should == 1
        $exceptions.should be_empty
      end
    end
  end
end
