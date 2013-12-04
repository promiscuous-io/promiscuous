require 'spec_helper'

describe Promiscuous, 'persisted models' do
  before do
    use_real_backend do |config|
      config.logger.level = Logger::FATAL
      config.ignore_exceptions = ignore_exceptions
      config.max_retries = 0
    end
  end
  before { load_models }
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
    let(:ignore_exceptions) { false }

    it 'blocks on the failed message' do
      sleep 1

      if ORM.has(:transaction)
        SubscriberModel.count.should == 0
      else
        SubscriberModel.first.field_1.should_not == 'ohai'
      end
    end
  end

  context 'when ignoring exceptions' do
    let(:ignore_exceptions) { true }

    it "doesn't block on the failed message" do
      eventually { SubscriberModel.first.field_1.should == 'ohai' }
    end
  end
end

describe Promiscuous, 'observers' do
  before do
    use_real_backend do |config|
      config.logger.level = Logger::FATAL
      config.ignore_exceptions = ignore_exceptions
      config.max_retries = 0
    end
  end
  before { load_models }
  before { load_observers }
  before { run_subscriber_worker! }
  before { $observer_counter = 0 }
  before do
    ModelObserver.class_eval do
      after_save do
        $observer_counter += 1
        raise "Something bad"
      end
    end
  end

  context 'when not ignoring exceptions' do
    let(:ignore_exceptions) { false }

    before do
      Promiscuous.context do
        pub = PublisherModel.create(:field_1 => 'value')
        pub.update_attributes(:field_1 => 'another value')
      end
    end

    it 'blocks on the failed message' do
      sleep 1

      $observer_counter.should == 1
    end
  end

  context 'when ignoring exceptions' do
    let(:ignore_exceptions) { true }

    before do
      Promiscuous.context do
        pub = PublisherModel.create(:field_1 => 'value')
        pub.update_attributes(:field_1 => 'another value')
      end
    end

    it "doesn't block on the failed message" do
      eventually { $observer_counter.should == 2 }
    end
  end
end
