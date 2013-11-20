require 'spec_helper'

describe Promiscuous do
  before { load_models }
  before { use_real_backend { |config| config.logger.level = Logger::FATAL } }
  before { run_subscriber_worker! }
  before do
    SubscriberModel.class_eval do
      after_save { raise "Something bad" if field_1 == 'raise' }
    end
  end
  before do
    Promiscuous.context do
      pub = PublisherModel.create(:field_1 => 'raise')
      pub.update_attributes(:field_1 => 'ohai')
    end
  end

  context 'when not ignoring exceptions' do
    before { Promiscuous::Config.ignore_exceptions = false }

    it 'blocks on the failed message' do
      sleep 1

      SubscriberModel.first.field_1.should_not == 'ohai'
    end
  end

  context 'when not ignoring exceptions' do
    before { Promiscuous::Config.ignore_exceptions = true }

    it "doesn't block on the failed message" do
      eventually { SubscriberModel.first.field_1.should == 'ohai' }
    end
  end
end
