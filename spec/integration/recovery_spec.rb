require 'spec_helper'

describe Promiscuous do
  before do
    @operation_klass = Promiscuous::Publisher::Operation::Base
    @operation_klass.stubs(:lock_options).returns(
      :timeout => 1.year,
      :sleep   => 0.1.seconds,
      :expire  => 0.seconds, # in reality, we'll have a 1 second expire time
      :lock_set => Promiscuous::Key.new(:pub).join('lock_set').to_s
    )

    use_fake_backend
    load_models
    run_subscriber_worker!
    Promiscuous::Config.recovery_timeout = 0.1
    @pub_worker = Promiscuous::Publisher::Worker.new
    @pub_worker.start
  end

  after { @pub_worker.stop }

  context 'when the publisher dies right after the locking' do
    it 'recovers' do
      pub = Promiscuous.context { PublisherModel.create(:field_1 => '1') }
      Promiscuous::AMQP::Fake.get_next_message

      @operation_klass.any_instance.stubs(:increment_read_and_write_dependencies).raises
      expect { Promiscuous.context { pub.update_attributes(:field_1 => '2') } }.to raise_error
      @operation_klass.any_instance.unstub(:increment_read_and_write_dependencies)

      Promiscuous.context { pub.update_attributes(:field_1 => '3') }

      payload = Promiscuous::AMQP::Fake.get_next_payload
      dep = payload['dependencies']
      dep['read'].should  == nil
      dep['write'].should == hashed["publisher_models/id/#{pub.id}:2"]
      payload['id'].should == pub.id.to_s
      payload['operation'].should == 'update'
      payload['payload']['field_1'].should == '3'
    end
  end

  context 'when the publisher dies during the increments' do
    it 'recovers' do
      PublisherModel.track_dependencies_of :field_2
      pub = Promiscuous.context { PublisherModel.create(:field_2 => 'hello') }
      Promiscuous::AMQP::Fake.get_next_message

      @num_deps = 10

      Promiscuous::Dependency.any_instance.stubs(:version=).raises
      expect { Promiscuous.context do
        @num_deps.times.map { |i| PublisherModel.where(:field_2 => i.to_s).count }
        pub.update_attributes(:field_1 => '1')
      end }.to raise_error
      Promiscuous::Dependency.any_instance.unstub(:version=)

      eventually { Promiscuous::AMQP::Fake.num_messages.should == 1 }

      payload = Promiscuous::AMQP::Fake.get_next_payload
      dep = payload['dependencies']
      dep['read'].should  == hashed[*@num_deps.times.map { |i| "publisher_models/field_2/#{i}:0" }]
      dep['write'].should == hashed["publisher_models/id/#{pub.id}:2",
                                    "publisher_models/field_2/hello:2"]
      payload['id'].should == pub.id.to_s
      payload['operation'].should == 'dummy'
      payload['payload'].should == nil
    end
  end

  context 'when the subscriber dies during the increments' do
    it 'recovers' do
      PublisherModel.track_dependencies_of :field_2
      pub = Promiscuous.context { PublisherModel.create(:field_2 => 'hello') }
      Promiscuous::AMQP::Fake.get_next_message

      NUM_DEPS = 10

      Promiscuous::Dependency.any_instance.stubs(:version=).raises
      expect { Promiscuous.context do
        NUM_DEPS.times.map { |i| PublisherModel.where(:field_2 => i.to_s).count }
        pub.update_attributes(:field_1 => '1')
      end }.to raise_error
      Promiscuous::Dependency.any_instance.unstub(:version=)

      eventually { Promiscuous::AMQP::Fake.num_messages.should == 1 }

      payload = Promiscuous::AMQP::Fake.get_next_payload
      dep = payload['dependencies']
      dep['read'].should  == hashed[*NUM_DEPS.times.map { |i| "publisher_models/field_2/#{i}:0" }]
      dep['write'].should == hashed["publisher_models/id/#{pub.id}:2",
                                    "publisher_models/field_2/hello:2"]
      payload['id'].should == pub.id.to_s
      payload['operation'].should == 'dummy'
      payload['payload'].should == nil
    end
  end

  context 'when the publisher dies right after the increments' do
    context 'when doing a create' do
      it 'recovers' do
        @operation_klass.any_instance.stubs(:perform_db_operation_with_no_exceptions).raises
        expect { Promiscuous.context { PublisherModel.create(:field_1 => '1') } }.to raise_error
        @operation_klass.any_instance.unstub(:perform_db_operation_with_no_exceptions)

        eventually { Promiscuous::AMQP::Fake.num_messages.should == 1 }

        pub = PublisherModel.first
        pub.field_1.should == '1'

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:1"]
        payload['id'].should == pub.id.to_s
        payload['operation'].should == 'create'
        payload['payload']['field_1'].should == '1'
      end
    end

    context 'when doing an update' do
      it 'recovers' do
        pub = Promiscuous.context { PublisherModel.create(:field_1 => '1') }
        Promiscuous::AMQP::Fake.get_next_message

        @operation_klass.any_instance.stubs(:perform_db_operation_with_no_exceptions).raises
        expect { Promiscuous.context { pub.update_attributes(:field_1 => '2') } }.to raise_error
        @operation_klass.any_instance.unstub(:perform_db_operation_with_no_exceptions)

        Promiscuous.context { pub.update_attributes(:field_1 => '3') }

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:2"]
        payload['id'].should == pub.id.to_s
        payload['operation'].should == 'dummy'
        payload['payload'].should == nil

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:3"]
        payload['id'].should == pub.id.to_s
        payload['operation'].should == 'update'
        payload['payload']['field_1'].should == '3'
      end
    end

    context 'when doing a destroy' do
      it 'recovers' do
        pub = Promiscuous.context { PublisherModel.create(:field_1 => '1') }
        Promiscuous::AMQP::Fake.get_next_message

        @operation_klass.any_instance.stubs(:perform_db_operation_with_no_exceptions).raises
        expect { Promiscuous.context { pub.destroy } }.to raise_error
        @operation_klass.any_instance.unstub(:perform_db_operation_with_no_exceptions)

        Promiscuous.context { pub.update_attributes(:field_1 => '3') }

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:2"]
        payload['id'].should == pub.id.to_s
        payload['operation'].should == 'dummy'
        payload['payload'].should == nil

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:3"]
        payload['id'].should == pub.id.to_s
        payload['operation'].should == 'update'
        payload['payload']['field_1'].should == '3'
      end
    end
  end

  context 'when the publisher takes its time to do the db query' do
    context 'when doing a create' do
      it 'recovers' do
        operation_klass = PublisherModel.get_operation_class_for(:create)
        operation_klass.any_instance.stubs(:going_to_execute_db_operation).with() do
          operation_klass.any_instance.unstub(:going_to_execute_db_operation)
          sleep 2
        end
        expect do
          Promiscuous.context { PublisherModel.create(:field_1 => '1') }
        end.to raise_error(Promiscuous::Error::LostLock)

        pub = PublisherModel.first
        pub.field_1.should == '1'

        Promiscuous.context { pub.update_attributes(:field_1 => '2') }

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:1"]
        payload['id'].should == pub.id.to_s
        payload['operation'].should == 'create'
        payload['payload']['field_1'].should == '1'

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:2"]
        payload['id'].should == pub.id.to_s
        payload['operation'].should == 'update'
        payload['payload']['field_1'].should == '2'
      end
    end

    context 'when doing an update' do
      it 'recovers' do
        pub = Promiscuous.context { PublisherModel.create(:field_1 => '1') }
        Promiscuous::AMQP::Fake.get_next_message

        operation_klass = PublisherModel.get_operation_class_for(:update)
        operation_klass.any_instance.stubs(:going_to_execute_db_operation).with() do
          operation_klass.any_instance.unstub(:going_to_execute_db_operation)
          sleep 2
        end
        expect do
          Promiscuous.context { pub.update_attributes(:field_1 => '2') }
        end.to raise_error(Promiscuous::Error::LostLock)

        Promiscuous.context { pub.update_attributes(:field_1 => '3') }

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:2"]
        payload['id'].should == pub.id.to_s
        payload['operation'].should == 'dummy'
        payload['payload'].should == nil

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:3"]
        payload['id'].should == pub.id.to_s
        payload['operation'].should == 'update'
        payload['payload']['field_1'].should == '3'
      end
    end

    context 'when doing a destroy' do
      it 'recovers' do
        pub = Promiscuous.context { PublisherModel.create(:field_1 => '1') }
        Promiscuous::AMQP::Fake.get_next_message

        operation_klass = PublisherModel.get_operation_class_for(:destroy)
        operation_klass.any_instance.stubs(:going_to_execute_db_operation).with() do
          operation_klass.any_instance.unstub(:going_to_execute_db_operation)
          sleep 2
        end
        expect do
          Promiscuous.context { pub.destroy }
        end.to raise_error(Promiscuous::Error::LostLock)

        Promiscuous.context { pub.update_attributes(:field_1 => '3') }

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:2"]
        payload['id'].should == pub.id.to_s
        payload['operation'].should == 'dummy'
        payload['payload'].should == nil

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:3"]
        payload['id'].should == pub.id.to_s
        payload['operation'].should == 'update'
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
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:1"]
        payload['id'].should == pub.id.to_s
        payload['operation'].should == 'create'
        payload['payload']['field_1'].should == '1'

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:2"]
        payload['id'].should == pub.id.to_s
        payload['operation'].should == 'update'
        payload['payload']['field_1'].should == '2'
      end
    end

    context 'when doing an update' do
      it 'recovers' do
        pub = Promiscuous.context { PublisherModel.create(:field_1 => '1') }
        Promiscuous::AMQP::Fake.get_next_message

        @operation_klass.any_instance.stubs(:publish_payload_in_redis).raises
        expect { Promiscuous.context { pub.update_attributes(:field_1 => '2') } }.to raise_error
        @operation_klass.any_instance.unstub(:publish_payload_in_redis)

        Promiscuous.context { pub.update_attributes(:field_1 => '3') }

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:2"]
        payload['id'].should == pub.id.to_s
        payload['operation'].should == 'dummy'
        payload['payload'].should == nil

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:3"]
        payload['id'].should == pub.id.to_s
        payload['operation'].should == 'update'
        payload['payload']['field_1'].should == '3'
      end
    end

    context 'when doing a destroy' do
      it 'recovers' do
        pub = Promiscuous.context { PublisherModel.create(:field_1 => '1') }
        Promiscuous::AMQP::Fake.get_next_message

        @operation_klass.any_instance.stubs(:publish_payload_in_redis).raises
        expect { Promiscuous.context { pub.destroy } }.to raise_error
        @operation_klass.any_instance.unstub(:publish_payload_in_redis)

        eventually(:timeout => 5.seconds) { Promiscuous::AMQP::Fake.num_messages.should == 1 }

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:2"]
        payload['id'].should == pub.id.to_s
        payload['operation'].should == 'dummy'
        payload['payload'].should == nil
      end
    end

    context 'when the lock times out' do
      it 'the app instance throws an exception' do
        pub = Promiscuous.context { PublisherModel.create(:field_1 => '1') }
        Promiscuous::AMQP::Fake.get_next_message

        @operation_klass.stubs(:lock_options).returns(
          :timeout => 0,
          :sleep   => 0.01.seconds,
          :expire  => 0.seconds,
          :lock_set => Promiscuous::Key.new(:pub).join('lock_set').to_s
        )

        @operation_klass.any_instance.stubs(:increment_read_and_write_dependencies).raises
        expect { Promiscuous.context { pub.update_attributes(:field_1 => '2') } }.to raise_error
        @operation_klass.any_instance.unstub(:increment_read_and_write_dependencies)

        expect do
          Promiscuous.context { pub.update_attributes(:field_1 => '3') }
        end.to raise_error(Promiscuous::Error::LockUnavailable)

      end
    end

    context 'when the publish to rabbitmq fails' do
      it 'republishes' do
        @operation_klass.any_instance.stubs(:publish_payload_in_rabbitmq_async).raises
        expect { Promiscuous.context { PublisherModel.create(:field_1 => '1') } }.to raise_error
        @operation_klass.any_instance.unstub(:publish_payload_in_rabbitmq_async)
        pub = PublisherModel.first

        eventually(:timeout => 5.seconds) { Promiscuous::AMQP::Fake.num_messages.should == 1 }

        message = Promiscuous::AMQP::Fake.get_next_message
        message[:key].should == 'test/publisher_model'
        payload = JSON.parse(message[:payload])
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:1"]
        payload['id'].should == pub.id.to_s
        payload['operation'].should == 'create'
        payload['payload']['field_1'].should == '1'
      end
    end

    context 'when locks are expiring' do
      it 'republishes' do
        @operation_klass.any_instance.stubs(:publish_payload_in_redis).raises
        expect { Promiscuous.context { PublisherModel.create(:field_1 => '1') } }.to raise_error
        @operation_klass.any_instance.unstub(:publish_payload_in_redis)
        pub = PublisherModel.first

        eventually(:timeout => 5.seconds) { Promiscuous::AMQP::Fake.num_messages.should == 1 }

        message = Promiscuous::AMQP::Fake.get_next_message
        message[:key].should == 'test/publisher_model'
        payload = JSON.parse(message[:payload])
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:1"]
        payload['id'].should == pub.id.to_s
        payload['operation'].should == 'create'
        payload['payload']['field_1'].should == '1'
      end
    end
  end
end
