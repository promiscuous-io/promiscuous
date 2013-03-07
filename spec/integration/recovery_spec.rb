require 'spec_helper'

describe Promiscuous do
  before do
    @operation_klass = Promiscuous::Publisher::Operation::Base
    @old_lock_options = @operation_klass::LOCK_OPTIONS
    @operation_klass.__send__(:remove_const, :LOCK_OPTIONS)
    # Hard to go down under one second because it's the granularity of our lock.
    @operation_klass::LOCK_OPTIONS = {:timeout => 5.seconds, :sleep => 0.01, :expire => 1.second}
  end

  after do
    @operation_klass.__send__(:remove_const, :LOCK_OPTIONS)
    @operation_klass::LOCK_OPTIONS = @old_lock_options
  end

  before { use_fake_backend }
  before { load_models }
  before { run_subscriber_worker! }

  context 'when the publisher dies right after the locking' do
    it 'recovers' do
      pub = Promiscuous.context { pub = PublisherModel.create(:field_1 => '1') }
      Promiscuous::AMQP::Fake.get_next_message

      @operation_klass.any_instance.stubs(:increment_read_and_write_dependencies).raises
      expect { Promiscuous.context { pub.update_attributes(:field_1 => '2') } }.to raise_error
      @operation_klass.any_instance.unstub(:increment_read_and_write_dependencies)

      Promiscuous.context { pub.update_attributes(:field_1 => '3') }

      payload = Promiscuous::AMQP::Fake.get_next_payload
      dep = payload['dependencies']
      dep['link'].should  == nil
      dep['read'].should  == nil
      dep['write'].should == ["publisher_models:id:#{pub.id}:2"]
      payload['payload']['field_1'].should == '3'
    end
  end

  context 'when the publisher dies right after the increments' do
    context 'when doing an update' do
      it 'recovers' do
        pub = Promiscuous.context { pub = PublisherModel.create(:field_1 => '1') }
        Promiscuous::AMQP::Fake.get_next_message

        @operation_klass.any_instance.stubs(:perform_db_operation_with_no_exceptions).raises
        expect { Promiscuous.context { pub.update_attributes(:field_1 => '2') } }.to raise_error
        @operation_klass.any_instance.unstub(:perform_db_operation_with_no_exceptions)

        Promiscuous.context { pub.update_attributes(:field_1 => '3') }

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['link'].should  == nil
        dep['read'].should  == nil
        dep['write'].should == ["publisher_models:id:#{pub.id}:2"]
        payload['operation'].should == 'dummy'
        payload['payload'].should == nil

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['link'].should  == nil
        dep['read'].should  == nil
        dep['write'].should == ["publisher_models:id:#{pub.id}:3"]
        payload['payload']['field_1'].should == '3'
      end
    end

    context 'when doing a destroy' do
      it 'recovers' do
        pub = Promiscuous.context { pub = PublisherModel.create(:field_1 => '1') }
        Promiscuous::AMQP::Fake.get_next_message

        @operation_klass.any_instance.stubs(:perform_db_operation_with_no_exceptions).raises
        expect { Promiscuous.context { pub.destroy } }.to raise_error
        @operation_klass.any_instance.unstub(:perform_db_operation_with_no_exceptions)

        Promiscuous.context { pub.update_attributes(:field_1 => '3') }

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['link'].should  == nil
        dep['read'].should  == nil
        dep['write'].should == ["publisher_models:id:#{pub.id}:2"]
        payload['operation'].should == 'dummy'
        payload['payload'].should == nil

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['link'].should  == nil
        dep['read'].should  == nil
        dep['write'].should == ["publisher_models:id:#{pub.id}:3"]
        payload['payload']['field_1'].should == '3'
      end
    end
  end

  context 'when the publisher dies right after the db operation' do
    context 'when doing a create' do
      it 'recovers' do
        @operation_klass.any_instance.stubs(:publish_payload_in_redis).raises
        expect { Promiscuous.context { PublisherModel.create(:field_1 => '1') } }.to raise_error
        @operation_klass.any_instance.unstub(:publish_payload_in_redis)

        pub = PublisherModel.first
        Promiscuous.context { pub.update_attributes(:field_1 => '2') }

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['link'].should  == nil
        dep['read'].should  == nil
        dep['write'].should == ["publisher_models:id:#{pub.id}:1"]
        payload['operation'].should == 'create'
        payload['payload']['field_1'].should == '1'

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['link'].should  == nil
        dep['read'].should  == nil
        dep['write'].should == ["publisher_models:id:#{pub.id}:2"]
        payload['operation'].should == 'update'
        payload['payload']['field_1'].should == '2'
      end
    end

    context 'when doing an update' do
      it 'recovers' do
        pub = Promiscuous.context { pub = PublisherModel.create(:field_1 => '1') }
        Promiscuous::AMQP::Fake.get_next_message

        @operation_klass.any_instance.stubs(:publish_payload_in_redis).raises
        expect { Promiscuous.context { pub.update_attributes(:field_1 => '2') } }.to raise_error
        @operation_klass.any_instance.unstub(:publish_payload_in_redis)

        Promiscuous.context { pub.update_attributes(:field_1 => '3') }

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['link'].should  == nil
        dep['read'].should  == nil
        dep['write'].should == ["publisher_models:id:#{pub.id}:2"]
        payload['operation'].should == 'update'
        payload['payload']['field_1'].should == '2'

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['link'].should  == nil
        dep['read'].should  == nil
        dep['write'].should == ["publisher_models:id:#{pub.id}:3"]
        payload['payload']['field_1'].should == '3'
      end
    end

    context 'when doing a destroy' do
      it 'recovers' do
        pub = Promiscuous.context { pub = PublisherModel.create(:field_1 => '1') }
        Promiscuous::AMQP::Fake.get_next_message

        @operation_klass.any_instance.stubs(:publish_payload_in_redis).raises
        expect { Promiscuous.context { pub.destroy } }.to raise_error
        @operation_klass.any_instance.unstub(:publish_payload_in_redis)

        # Manually triggering the recovery, but we should have a worker.
        key = pub.promiscuous.tracked_dependencies.first.key(:pub).to_s
        Promiscuous::Publisher::Operation::Base.recover_payload_for(key)

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['link'].should  == nil
        dep['read'].should  == nil
        dep['write'].should == ["publisher_models:id:#{pub.id}:2"]
        payload['operation'].should == 'destroy'
        payload['payload'].should == nil
      end
    end
  end
end
