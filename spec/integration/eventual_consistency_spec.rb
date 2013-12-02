require 'spec_helper'

if ORM.has(:mongoid)
  describe Promiscuous do
    before { use_real_backend { |config| config.consistency = consistency } }
    before { load_models }
    before { run_subscriber_worker! }
    before { $callback_counter = 0 }
    before do
      SubscriberModel.class_eval do
        after_save { $callback_counter += 1 }
      end
    end

    context 'when updates are processed out of order' do
      before { Promiscuous::Config.logger.level = logger_level }
      before do
        pub = Promiscuous.context { PublisherModel.create(:field_1 => '1') }
        eventually { SubscriberModel.count.should == 1 }

        stub_before_hook(Promiscuous::Publisher::Operation::Base, :publish_payload_in_rabbitmq_async) do |control|
          control.unstub!
          Thread.new { Promiscuous.context { pub.update_attributes(:field_1 => '3') } }.join
          sleep 0.1
        end

        Promiscuous.context { pub.update_attributes(:field_1 => '2') }

        sleep 1
      end
      let(:logger_level) { Logger::INFO }

      context 'when consistency is none' do
        let(:consistency) { :none }

        it 'subscribes to messages out of order' do
          eventually do
            SubscriberModel.first.field_1.should be_in ['2','3']
            $callback_counter.should be_in [2, 3]
          end
        end
      end

      context 'when consistency is eventual' do
        # We get some skipped message warning
        let(:logger_level) { Logger::FATAL }
        let(:consistency)  { :eventual }

        it 'subscribes to messages in the correct order (by dropping the last message)' do
          eventually do
            SubscriberModel.first.field_1.should == '3'
            $callback_counter.should == 2
          end
        end
      end

      context 'when consistency is causal' do
        let(:consistency) { :causal }

        it 'subscribes to messages in the correct order (by waiting for lost message)' do
          eventually do
            SubscriberModel.first.field_1.should == '3'
            $callback_counter.should == 3
          end
        end
      end
    end

    context 'when create/update are processed out of order' do
      # We get some upsert warnings
      before { Promiscuous::Config.logger.level = Logger::FATAL }

      before do
        stub_before_hook(Promiscuous::Publisher::Operation::Base, :publish_payload_in_rabbitmq_async) do |control|
          control.unstub!
          Thread.new { Promiscuous.context { PublisherModel.first.update_attributes(:field_1 => '2') } }.join
          sleep 0.1
        end

        Promiscuous.context { PublisherModel.create(:field_1 => '1') }

        sleep 1
      end

      context 'when consistency is none' do
        let(:consistency) { :none }

        it 'subscribes to messages out of order' do
          eventually do
            SubscriberModel.first.field_1.should be_in ['1','2']
            $callback_counter.should be_in [1, 2]
          end
        end
      end

      context 'when consistency is eventual' do
        let(:consistency) { :eventual }

        it 'subscribes to messages in the correct order (by dropping the last message)' do
          eventually do
            SubscriberModel.first.field_1.should == '2'
            $callback_counter.should == 1
          end
        end
      end

      context 'when consistency is causal' do
        let(:consistency) { :causal }

        it 'subscribes to messages in the correct order (by waiting for lost message)' do
          eventually do
            SubscriberModel.first.field_1.should == '2'
            $callback_counter.should == 2
          end
        end
      end
    end

    context 'when (create|update)/destroy are processed out of order' do
      before { Promiscuous::Config.logger.level = Logger::FATAL }

      before do
        stub_before_hook(Promiscuous::Publisher::Operation::Base, :publish_payload_in_rabbitmq_async) do |control|
          control.unstub!
          Thread.new { Promiscuous.context { PublisherModel.first.destroy } }.join
          sleep 0.1
        end

        Promiscuous.context { PublisherModel.create(:field_1 => '1') }

        sleep 1
      end

      context 'when consistency is eventual' do
        let(:consistency) { :eventual }

        before do
          Promiscuous::Subscriber::Worker::EventualDestroyer.stubs(:destroy_timeout).returns(3.second)
          Promiscuous::Subscriber::Worker::EventualDestroyer.stubs(:check_every).returns(1.second)
          @worker.eventual_destroyer.stop
          @worker.eventual_destroyer.start
        end

        it 'subscribes to messages in the correct order (by dropping the last message)' do
          eventually(:timeout => 10.seconds) { SubscriberModel.count.should == 0 }
          Promiscuous::Subscriber::Worker::EventualDestroyer::PendingDestroy.count.should == 0
        end
      end

      context 'when consistency is causal' do
        let(:consistency) { :causal }

        it 'subscribes to messages in the correct order (by waiting for lost message)' do
          eventually { SubscriberModel.count.should == 0 }
        end
      end
    end

    context 'when a message is lost' do
      before do
        pub = Promiscuous.context { PublisherModel.create(:field_1 => '1') }
        eventually { SubscriberModel.count.should == 1 }

        stub_before_hook(Promiscuous::Publisher::Operation::Base, :publish_payload_in_rabbitmq_async) do |control|
          control.unstub!
          control.skip_next_call!
        end

        Promiscuous.context { pub.update_attributes(:field_1 => '2') } # this payload will never be sent
        Promiscuous.context { pub.update_attributes(:field_1 => '3') }
      end

      context 'when consistency is none' do
        let(:consistency) { :none }

        it 'does whatever it wants' do
          eventually { SubscriberModel.first.field_1.should be_in ['1','3'] }
        end
      end

      context 'when consistency is eventual' do
        let(:consistency) { :eventual }

        it 'replicates to the last value' do
          eventually { SubscriberModel.first.field_1.should == '3' }
        end
      end

      context 'when consistency is causal' do
        let(:consistency) { :causal }

        it 'blocks waiting for the missing message' do
          eventually { SubscriberModel.first.field_1.should == '1' }
        end
      end
    end

    context 'when consistency is eventual' do
      let(:consistency) { :eventual }

      context 'when an update comes on an alreay existing database' do
        it 'replicates properly' do
          without_promiscuous do
            pub = PublisherModel.create(:field_1 => 'hello')
            SubscriberModel.new.tap { |sub| sub.id = pub.id; sub.field_1 = 'hello' }.save
          end

          Promiscuous.context { PublisherModel.first.update_attributes(:field_1 => 'ohai') }
          eventually { SubscriberModel.first.field_1.should == 'ohai' }
          SubscriberModel.count.should == 1
        end
      end
    end
  end
end
