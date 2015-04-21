require 'spec_helper'

describe Promiscuous do
  let(:lock_expiration) { 1 }

  before { use_real_backend { |config| config.logger.level = Logger::ERROR
                              config.publisher_lock_expiration = lock_expiration
                              config.publisher_lock_timeout    = 0.1
                              config.recovery_interval = 0.1 } }
  before { load_models }
  before { run_subscriber_worker! }

  after { redis_lock_count.should == 0 }

  context "when a recovery worker is running" do
    before { run_recovery_worker! }

    context 'when backend dies' do
      context 'for updates' do
        it 'still publishes message' do
          pub = PublisherModel.create(:field_1 => '1')

          eventually { SubscriberModel.count.should == 1 }

          backend_down!

          expect { pub.update_attributes(:field_1 => '2') }.to_not raise_error

          sleep 10

          SubscriberModel.first.field_1.should == '1'

          backend_up!

          eventually do
            SubscriberModel.first.field_1.should == '2'
          end
        end
      end

      context 'for creates' do
        it 'still publishes message updates' do
          backend_down!

          expect { PublisherModel.create(:field_1 => '1') }.to_not raise_error

          sleep 1

          SubscriberModel.count.should == 0

          backend_up!

          eventually { SubscriberModel.first.field_1.should == '1' }
        end
      end

      context "for two operations on the same document" do
        it "raises for the second operation as the lock has not expired" do
          backend_down!

          pub = PublisherModel.create(:field_1 => '1')
          expect { pub.destroy }.to raise_error

          backend_up!

          eventually { redis_lock_count.should == 0 }
        end
      end

      context 'destroys' do
        it 'still publishes message updates' do
          pub = PublisherModel.create(:field_1 => '1')

          eventually { SubscriberModel.count.should == 1 }

          backend_down!

          expect { pub.destroy }.to_not raise_error

          sleep 1

          SubscriberModel.count.should == 1

          backend_up!

          eventually { SubscriberModel.count.should == 0 }
        end
      end

      context 'ephemerals' do
        before { load_ephemerals }

        it 'raises if unable to publish' do
          backend_down!

          expect { ModelEphemeral.create(:field_1 => '1') }.to raise_error
          SubscriberModel.count.should == 0

          backend_up!

          expect { ModelEphemeral.create(:field_1 => '1') }.to_not raise_error
          eventually { SubscriberModel.first.field_1.should == '1' }
        end
      end
    end
  end

  context "when a recovery worker is not running" do
    context "backend dies" do
      let(:lock_expiration) { 0.1 }

      before { $field_values = [] }
      before do
        SubscriberModel.class_eval do
          after_save { $field_values << self.field_2 }
        end
      end
      before { backend_down! }

      it "multiple subsequent operation fail if backend is down until backend comes back up" do
        @pub = PublisherModel.create(:field_2 => '1')
        sleep 1
        expect { @pub.update_attributes(:field_2 => '2') }.to raise_error
        sleep 1
        expect { @pub.update_attributes(:field_2 => '3') }.to raise_error
        sleep 1

        backend_up!

        expect { @pub.update_attributes(:field_2 => '4') }.to_not raise_error

        eventually do
          $field_values.should == ['1', '4']
        end
      end
    end
  end
end
