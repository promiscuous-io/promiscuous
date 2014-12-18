require 'spec_helper'

describe Promiscuous do
  before { use_real_backend { |config| config.logger.level = Logger::ERROR
                              config.publisher_lock_expiration = 2
                              config.publisher_lock_timeout    = 0.1
                              config.recovery_interval = 0.01 } }
  before { run_recovery_worker! }
  before { load_models }
  before { run_subscriber_worker! }

  after { Promiscuous::Publisher::Transport.expired.should be_empty }

  context 'when rabbit dies' do
    context 'for updates' do
      it 'still publishes message' do
        pub = PublisherModel.create(:field_1 => '1')

        eventually { SubscriberModel.count.should == 1 }

        amqp_down!

        expect { pub.update_attributes(:field_1 => '2') }.to_not raise_error

        sleep 0.1

        SubscriberModel.count.should == 1

        amqp_up!

        eventually { SubscriberModel.first.field_1.should == '2' }
      end
    end

    context 'for creates' do
      it 'still publishes message updates' do
        amqp_down!

        expect { PublisherModel.create(:field_1 => '1') }.to_not raise_error

        sleep 0.1

        SubscriberModel.count.should == 0

        amqp_up!

        eventually { SubscriberModel.first.field_1.should == '1' }
      end
    end

    context "for two operations on the same document" do
      it "raises for the second operation as the lock has not expired" do
        amqp_down!

        pub = PublisherModel.create(:field_1 => '1')
        expect { pub.destroy }.to raise_error

        amqp_up!

        eventually { Promiscuous::Publisher::Transport.expired.should be_empty }
      end
    end

    context 'destroys' do
      it 'still publishes message updates' do
        pub = PublisherModel.create(:field_1 => '1')

        eventually { SubscriberModel.count.should == 1 }

        amqp_down!

        expect { pub.destroy }.to_not raise_error

        sleep 0.1

        SubscriberModel.count.should == 1

        amqp_up!

        eventually { SubscriberModel.count.should == 0 }
      end
    end

    context 'ephemerals' do
      before { load_ephemerals }

      it 'raises if unable to publish' do
        amqp_down!

        expect { ModelEphemeral.create(:field_1 => '1') }.to raise_error
        SubscriberModel.count.should == 0

        amqp_up!

        expect { ModelEphemeral.create(:field_1 => '1') }.to_not raise_error
        eventually { SubscriberModel.first.field_1.should == '1' }
      end
    end
  end
end
