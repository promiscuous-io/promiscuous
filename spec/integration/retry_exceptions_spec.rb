require 'spec_helper'

describe Promiscuous do
  before { load_models }
  before { use_real_backend { |config| config.logger.level = Logger::FATAL } }
  before { run_subscriber_worker! }
  before { $raise = true }
  before do
    SubscriberModel.class_eval do
      after_save { raise "Something bad" if $raise  }
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

    $raise = false; sleep 2

    SubscriberModel.count.should == 1
  end
end
