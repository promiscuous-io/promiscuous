require 'spec_helper'

describe Promiscuous do
  before { load_models }
  before { use_real_backend }
  before { record_callbacks(SubscriberModel) }

  before { run_subscriber_worker! }

  if ORM.has(:mongoid)
    context 'when doing a blank update' do
      it 'passes through' do
        pub1 = Promiscuous.transaction { PublisherModel.create(:field_1 => '1') }
        eventually { SubscriberModel.first.should_not == nil }
        Mongoid.purge!
        expect { Promiscuous.transaction { pub1.update_attributes(:field_1 => '2') } }.to_not raise_error
      end
    end

    context 'when doing a blank destroy' do
      it 'passes through' do
        pub1 = Promiscuous.transaction { PublisherModel.create(:field_1 => '1') }
        eventually { SubscriberModel.first.should_not == nil }
        Mongoid.purge!
        expect { Promiscuous.transaction { pub1.destroy } }.to_not raise_error
      end
    end

    context 'when doing multi updates' do
      it 'fails immediately' do
        expect { Promiscuous.transaction { PublisherModel.update_all(:field_1 => '1') } }.to raise_error
      end
    end

    context 'when doing multi delete' do
      it 'fails immediately' do
        expect { Promiscuous.transaction { PublisherModel.delete_all(:field_1 => '1') } }.to raise_error
      end
    end
  end

  context 'with total ordering' do
    context 'when the messages arrive out of order', :pending => true do
      it 'replicates' do
        ORM::Operation.any_instance.stubs(:version).returns(
          {:global => 1}, {:global => 3}, {:global => 2}
        )

        pub = PublisherModel.create(:field_1 => '1')
        pub.update_attributes(:field_1 => '2')
        pub.update_attributes(:field_1 => '3')

        eventually do
          SubscriberModel.first.field_1.should == '2'
          SubscriberModel.num_saves.should == 3
        end
      end
    end

    context 'when the messages are duplicated', :pending => true do
      it 'does not replicate the duplicates' do
        ORM::Operation.any_instance.stubs(:version).returns(
          {:global => 1}, {:global => 2}, {:global => 1}, {:global => 3}
        )

        pub = PublisherModel.create
        pub.update_attributes(:field_1 => '1')
        pub.update_attributes(:field_1 => '2')
        pub.update_attributes(:field_1 => '3')

        sleep 0.5 # Avoid killing runners too soon

        eventually do
          SubscriberModel.first.field_1.should == '3'
          SubscriberModel.num_saves.should == 3
        end
      end
    end

    context 'when subscribing to a subset of models' do
      it 'replicates' do
        Promiscuous.transaction do
          PublisherModel.create
          PublisherModelOther.create
          PublisherModel.create
        end

        eventually do
          SubscriberModel.num_saves.should == 2
        end
      end
    end

    context 'when the publisher fails' do
      it 'replicates' do
        Promiscuous.transaction do
          pub1 = PublisherModel.create(:field_1 => '1')
          expect do
            PublisherModel.create({:id => pub1.id, :field_1 => '2'}, :without_protection => true)
          end.to raise_error
          pub3 = PublisherModel.create(:field_1 => '3')
        end

        eventually do
          SubscriberModel.count.should == 2
        end
      end
    end

    context 'when the worker is blocking in recovery mode', :pending => true do
      before do
        config_logger(:logger_level => Logger::FATAL)
        Promiscuous::Config.prefetch = 3
        Promiscuous::Config.recovery = true
      end

      it 'recovers' do
        ORM::Operation.any_instance.stubs(:version).returns(
          {:global => 10}, {:global => 11}, {:global => 12}
        )

        pub = PublisherModel.create(:field_1 => '1')
        pub.update_attributes(:field_1 => '2')
        pub.update_attributes(:field_1 => '3')

        eventually do
          SubscriberModel.first.field_1.should == '3'
        end
      end
    end
  end
end
