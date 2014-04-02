require 'spec_helper'

describe Promiscuous do
  let(:destroy_timeout)        { 0 }
  let(:destroy_check_interval) { 0 }

  before do
    use_real_backend { |config|
      config.destroy_timeout = destroy_timeout
      config.destroy_check_interval = destroy_check_interval
    }
  end
  before { load_models }
  before { run_subscriber_worker! }
  before { $callback_counter = 0 }
  before do
    SubscriberModel.class_eval do
      after_save { $callback_counter += 1 }
    end
  end

  context 'when subscribing to an observer' do
    before { load_observers }

    it "subscribes" do
      define_callback(:update)
      PublisherModel.create(:field_1 => '1').update_attributes(:field_1 => '2')

      eventually { ModelObserver.update_instance.should be_present }
    end
  end

  context 'with create operations' do
    before do
      PublisherModel.create(:field_1 => '1')
    end

    it "stores the version number" do
      eventually { SubscriberModel.first._v.should_not == nil }
    end
  end

  context 'when updates are processed out of order' do
    before { Promiscuous::Config.logger.level = Logger::FATAL }
    before do
      pub = PublisherModel.create(:field_1 => '1')
      eventually { SubscriberModel.count.should == 1 }

      stub_before_hook(Promiscuous::Publisher::Operation::Base, :publish_payload_in_rabbitmq_async) do |control|
        control.unstub!
        Thread.new { pub.update_attributes(:field_1 => '3') }.join
        sleep 0.1
      end

      pub.update_attributes(:field_1 => '2')

      sleep 1
    end

    it 'subscribes to messages in the correct order (by dropping the last message)' do
      eventually do
        SubscriberModel.first.field_1.should == '3'
        $callback_counter.should == 2
      end
    end
  end

  context 'when create/update are processed out of order' do
    # We get some upsert warnings
    before { Promiscuous::Config.logger.level = Logger::FATAL }

    before do
      stub_before_hook(Promiscuous::Publisher::Operation::Base, :publish_payload_in_rabbitmq_async) do |control|
        control.unstub!
        Thread.new { PublisherModel.first.update_attributes(:field_1 => '2') }.join
        sleep 0.1
      end

      PublisherModel.create(:field_1 => '1')

      sleep 1
    end

    it 'subscribes to messages in the correct order (by dropping the last message)' do
      eventually do
        SubscriberModel.first.field_1.should == '2'
        $callback_counter.should == 1
      end
    end
  end

  context 'when (create|update)/destroy are processed out of order' do
    before { Promiscuous::Config.logger.level = Logger::FATAL }

    before do
      stub_before_hook(Promiscuous::Publisher::Operation::Base, :publish_payload_in_rabbitmq_async) do |control|
        control.unstub!
        Thread.new { PublisherModel.first.destroy }.join
        sleep 0.1
      end

      PublisherModel.create(:field_1 => '1')

      sleep 1
    end

    context 'within the timeout' do
      let(:destroy_timeout)        { 3.seconds }
      let(:destroy_check_interval) { 1.seconds }

      before do
        @worker.eventual_destroyer.stop
        @worker.eventual_destroyer.start
      end

      it 'subscribes to messages in the correct order (by dropping the last message)' do
        eventually(:timeout => 10.seconds) { SubscriberModel.count.should == 0 }
        Promiscuous::Subscriber::Worker::EventualDestroyer::PendingDestroy.count.should == 0
      end
    end

    context 'not within the timeout' do
      let(:destroy_timeout)        { 10.seconds }
      let(:destroy_check_interval) { 1.seconds }

      before do
        @worker.eventual_destroyer.stop
        @worker.eventual_destroyer.start
      end

      it 'subscribes to messages in the correct order (by dropping the last message)' do
        sleep 1

        SubscriberModel.count.should == 1
        Promiscuous::Subscriber::Worker::EventualDestroyer::PendingDestroy.count.should == 1
      end
    end
  end

  context 'when a message is lost' do
    before do
      pub = PublisherModel.create(:field_1 => '1')
      eventually { SubscriberModel.count.should == 1 }

      stub_before_hook(Promiscuous::Publisher::Operation::Base, :publish_payload_in_rabbitmq_async) do |control|
        control.unstub!
        control.skip_next_call!
      end

      pub.update_attributes(:field_1 => '2') # this payload will never be sent
      pub.update_attributes(:field_1 => '3')
    end

    it 'replicates to the last value' do
      eventually { SubscriberModel.first.field_1.should == '3' }
    end
  end

  context 'when an update comes on an alreay existing database' do
    it 'replicates properly' do
      without_promiscuous do
        pub = PublisherModel.create(:field_1 => 'hello')
        SubscriberModel.new.tap { |sub| sub.id = pub.id; sub.field_1 = 'hello' }.save
      end

      PublisherModel.first.update_attributes(:field_1 => 'ohai')
      eventually { SubscriberModel.first.field_1.should == 'ohai' }
      SubscriberModel.count.should == 1
    end
  end
end

def define_callback(cb)
  ModelObserver.class_eval do
    cattr_accessor "#{cb}_instance"
    __send__("after_#{cb}", proc { self.class.send("#{cb}_instance=", self) })
  end
end
