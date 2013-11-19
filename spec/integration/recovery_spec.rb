require 'spec_helper'

describe Promiscuous do
  before do

    @proxy_klass = Promiscuous::Publisher::Operation::ProxyForQuery
    @operation_klass = Promiscuous::Publisher::Operation::Base
    @operation_klass.stubs(:lock_options).returns(
      :timeout => 1.year,
      :sleep   => 0.1.seconds,
      :expire  => 1.second,
      :lock_set => Promiscuous::Key.new(:pub).join('lock_set').to_s
    )

    use_fake_backend
    load_models

    Promiscuous::Config.recovery_timeout = 0.1

    @pub_worker = Promiscuous::Publisher::Worker.new
    @pub_worker.start
  end

  def stub_once_on(klass, method, options={}, &block)
    stub_before_hook(klass, method) do |control|
      if !options[:if] || options[:if].call(control.instance, control.arguments)
        control.unstub!
        block.call(control.instance)
      end
    end
  end

  def stub_once_on_db_query(&block)
    stub_once_on(@proxy_klass, :call_and_remember_result,
                 :if => proc { |op, args| caller.grep(/non_persistent/).empty? && # Really sad hack
                                          args[0] == :instrumented }, &block)
  end

  after { @pub_worker.stop }

  context 'when the publisher dies right before doing increments' do
    it 'recovers' do
      pub = Promiscuous.context { PublisherModel.create(:field_1 => '1') }
      Promiscuous::AMQP::Fake.get_next_message

      stub_once_on(@operation_klass, :increment_read_and_write_dependencies) { raise }
      expect { Promiscuous.context { pub.update_attributes(:field_1 => '2') } }.to raise_error

      Promiscuous.context { pub.update_attributes(:field_1 => '3') }

      payload = Promiscuous::AMQP::Fake.get_next_payload
      dep = payload['dependencies']
      dep['read'].should  == nil
      dep['write'].should == hashed["publisher_models/id/#{pub.id}:2"]
      op = payload['operations'].first
      op['id'].should == pub.id.to_s
      op['operation'].should == 'update'
      op['attributes']['field_1'].should == '3'
    end
  end

  context 'when the subscriber dies in the middle of doing the increments' do
    it 'recovers' do
      PublisherModel.track_dependencies_of :field_2
      pub = Promiscuous.context { PublisherModel.create(:field_2 => 'hello') }
      Promiscuous::AMQP::Fake.get_next_message

      NUM_DEPS = 10

      # Raising on version= will simulate a failure right after the master node
      # access.
      stub_once_on(Promiscuous::Dependency, :version=) { raise }
      expect { Promiscuous.context do
        NUM_DEPS.times.map { |i| PublisherModel.where(:field_2 => i.to_s).count }
        pub.update_attributes(:field_1 => '1')
      end }.to raise_error

      eventually { Promiscuous::AMQP::Fake.num_messages.should == 1 }

      payload = Promiscuous::AMQP::Fake.get_next_payload
      dep = payload['dependencies']
      dep['read'].should  =~ hashed[*NUM_DEPS.times.map { |i| "publisher_models/field_2/#{i}:0" }]
      dep['write'].should =~ hashed["publisher_models/id/#{pub.id}:2", "publisher_models/field_2/hello:2"]

      op = payload['operations'].first
      op['id'].should == pub.id.to_s
      op['operation'].should == 'update'
      if ORM.has(:transaction)
        op['attributes']['field_1'].should == '1'
      else
        op['attributes']['field_1'].should == nil
      end
    end
  end

  context 'when the publisher dies right after the increments' do
    context 'when doing a create' do
      it 'recovers' do
        stub_once_on_db_query { raise }
        expect { Promiscuous.context { PublisherModel.create(:field_1 => '1') } }.to raise_error

        eventually { Promiscuous::AMQP::Fake.num_messages.should == 1 }

        pub = PublisherModel.first
        pub.field_1.should == '1'

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:1"]
        op = payload['operations'].first
        op['id'].should == pub.id.to_s
        op['operation'].should == 'create'
        op['attributes']['field_1'].should == '1'
      end
    end

    context 'when doing an update' do
      it 'recovers' do
        pub = Promiscuous.context { PublisherModel.create(:field_1 => '1') }
        Promiscuous::AMQP::Fake.get_next_message

        stub_once_on_db_query { raise }
        expect { Promiscuous.context { pub.update_attributes(:field_1 => '2') } }.to raise_error

        eventually { Promiscuous::AMQP::Fake.num_messages.should == 1 } if ORM.has(:transaction)

        Promiscuous.context { pub.update_attributes(:field_1 => '3') }

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:2"]
        op = payload['operations'].first
        op['id'].should == pub.id.to_s
        op['operation'].should == 'update'
        if ORM.has(:transaction)
          op['attributes']['field_1'] == '2'
        else
          op['attributes']['field_1'] == '1'
        end

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:3"]
        op = payload['operations'].first
        op['id'].should == pub.id.to_s
        op['operation'].should == 'update'
        op['attributes']['field_1'].should == '3'
      end
    end

    if ORM.has(:mongoid)
      context 'when doing an update, but the document is gone due to a dataloss on the db' do
        it 'recovers without an operation' do
          Promiscuous::Config.logger.level = Logger::FATAL

          pub = Promiscuous.context { PublisherModel.create(:field_1 => '1') }
          Promiscuous::AMQP::Fake.get_next_message

          stub_once_on_db_query do
            without_promiscuous { pub.delete }
            raise
          end
          expect { Promiscuous.context { pub.update_attributes(:field_1 => '2') } }.to raise_error

          PublisherModel.count.should == 0

          eventually { Promiscuous::AMQP::Fake.num_messages.should == 1 }

          payload = Promiscuous::AMQP::Fake.get_next_payload
          dep = payload['dependencies']
          dep['read'].should  == nil
          dep['write'].should == hashed["publisher_models/id/#{pub.id}:2"]
          payload['operations'].count.should == 0
        end
      end
    end

    context 'when doing a destroy' do
      it 'recovers' do
        pub = Promiscuous.context { PublisherModel.create(:field_1 => '1') }
        Promiscuous::AMQP::Fake.get_next_message

        stub_once_on_db_query { raise }
        expect { Promiscuous.context { pub.destroy } }.to raise_error

        Promiscuous.context { pub.update_attributes(:field_1 => '3') }

        eventually { Promiscuous::AMQP::Fake.num_messages.should == 1 }

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:2"]
        op = payload['operations'].first
        op['id'].should == pub.id.to_s
        op['operation'].should == 'destroy'
        op['attributes'].should == nil
      end
    end
  end

  context 'when the publisher takes its time to do the db query' do
    context 'when doing a create' do
      it 'recovers' do

        stub_once_on_db_query { sleep 2 }
        expect do
          Promiscuous.context { PublisherModel.create(:field_1 => '1') }
        end.to raise_error(Promiscuous::Error::LostLock)

        eventually { Promiscuous::AMQP::Fake.num_messages.should == 1 }

        pub = PublisherModel.first
        pub.field_1.should == '1'

        Promiscuous.context { pub.update_attributes(:field_1 => '2') }

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:1"]
        op = payload['operations'].first
        op['id'].should == pub.id.to_s
        op['operation'].should == 'create'
        op['attributes']['field_1'].should == '1'

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:2"]
        op = payload['operations'].first
        op['id'].should == pub.id.to_s
        op['operation'].should == 'update'
        op['attributes']['field_1'].should == '2'
      end
    end

    context 'when doing an update' do
      it 'recovers' do
        pub = Promiscuous.context { PublisherModel.create(:field_1 => '1') }
        Promiscuous::AMQP::Fake.get_next_message

        stub_once_on_db_query { sleep 2 }
        expect do
          Promiscuous.context { pub.update_attributes(:field_1 => '2') }
        end.to raise_error(Promiscuous::Error::LostLock)

        Promiscuous.context { pub.update_attributes(:field_1 => '3') }

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:2"]
        op = payload['operations'].first
        op['id'].should == pub.id.to_s
        op['operation'].should == 'update'

        if ORM.has(:transaction)
          op['attributes']['field_1'].should == '2'
        else
          op['attributes']['field_1'].should == '1'
        end

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:3"]
        op = payload['operations'].first
        op['id'].should == pub.id.to_s
        op['operation'].should == 'update'
        op['attributes']['field_1'].should == '3'
      end
    end

    context 'when doing a destroy' do
      it 'recovers' do
        pub = Promiscuous.context { PublisherModel.create(:field_1 => '1') }
        Promiscuous::AMQP::Fake.get_next_message

        stub_once_on_db_query { sleep 2 }
        expect do
          Promiscuous.context { pub.destroy }
        end.to raise_error(Promiscuous::Error::LostLock)

        Promiscuous.context { pub.update_attributes(:field_1 => '3') }

        eventually { Promiscuous::AMQP::Fake.num_messages.should == 1 }

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:2"]
        op = payload['operations'].first
        op['id'].should == pub.id.to_s
        op['operation'].should == 'destroy'
        op['attributes'].should == nil
      end
    end
  end

  context 'when the publisher dies right after the db operation' do
    context 'when doing a create' do
      it 'recovers' do
        stub_once_on(@operation_klass, :publish_payload_in_redis) { raise }

        expect { Promiscuous.context { PublisherModel.create(:field_1 => '1') } }.to raise_error

        eventually { Promiscuous::AMQP::Fake.num_messages.should == 1 } if ORM.has(:transaction)

        pub = PublisherModel.first
        Promiscuous.context { pub.update_attributes(:field_1 => '2') }

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:1"]
        op = payload['operations'].first
        op['id'].should == pub.id.to_s
        op['operation'].should == 'create'
        op['attributes']['field_1'].should == '1'

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:2"]
        op = payload['operations'].first
        op['id'].should == pub.id.to_s
        op['operation'].should == 'update'
        op['attributes']['field_1'].should == '2'
      end
    end

    context 'when doing an update' do
      it 'recovers' do
        pub = Promiscuous.context { PublisherModel.create(:field_1 => '1') }
        Promiscuous::AMQP::Fake.get_next_message

        stub_once_on(@operation_klass, :publish_payload_in_redis) { raise }
        expect { Promiscuous.context { pub.update_attributes(:field_1 => '2') } }.to raise_error

        eventually { Promiscuous::AMQP::Fake.num_messages.should == 1 } if ORM.has(:transaction)

        Promiscuous.context { pub.update_attributes(:field_1 => '3') }

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:2"]
        op = payload['operations'].first
        op['id'].should == pub.id.to_s
        op['operation'].should == 'update'
        if ORM.has(:transaction)
          op['attributes']['field_1'] == '2'
        else
          op['attributes']['field_1'] == '1'
        end

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:3"]
        op = payload['operations'].first
        op['id'].should == pub.id.to_s
        op['operation'].should == 'update'
        op['attributes']['field_1'].should == '3'
      end
    end

    context 'when doing a destroy' do
      it 'recovers' do
        pub = Promiscuous.context { PublisherModel.create(:field_1 => '1') }
        Promiscuous::AMQP::Fake.get_next_message

        stub_once_on(@operation_klass, :publish_payload_in_redis) { raise }
        expect { Promiscuous.context { pub.destroy } }.to raise_error

        eventually { Promiscuous::AMQP::Fake.num_messages.should == 1 }

        payload = Promiscuous::AMQP::Fake.get_next_payload
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:2"]
        op = payload['operations'].first
        op['id'].should == pub.id.to_s
        op['operation'].should == 'destroy'
        op['attributes'].should == nil
      end
    end

    context 'when the lock times out' do
      it 'the app instance throws an exception' do
        pub = Promiscuous.context { PublisherModel.create(:field_1 => '1') }
        Promiscuous::AMQP::Fake.get_next_message

        @operation_klass.stubs(:lock_options).returns(
          :timeout => 0,
          :sleep   => 0.01.seconds,
          :expire  => 1.second,
          :lock_set => Promiscuous::Key.new(:pub).join('lock_set').to_s
        )

        stub_once_on(@operation_klass, :increment_read_and_write_dependencies) { raise }

        expect { Promiscuous.context { pub.update_attributes(:field_1 => '2') } }.to raise_error

        expect do
          Promiscuous.context { pub.update_attributes(:field_1 => '3') }
        end.to raise_error(Promiscuous::Error::LockUnavailable)
      end
    end

    context 'when the publish to rabbitmq fails' do
      it 'republishes' do
        stub_once_on(@operation_klass, :publish_payload_in_rabbitmq_async) { raise }
        expect { Promiscuous.context { PublisherModel.create(:field_1 => '1') } }.to raise_error
        pub = PublisherModel.first

        eventually { Promiscuous::AMQP::Fake.num_messages.should == 1 }

        message = Promiscuous::AMQP::Fake.get_next_message
        payload = JSON.parse(message[:payload])
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:1"]
        op = payload['operations'].first
        op['id'].should == pub.id.to_s
        op['operation'].should == 'create'
        op['attributes']['field_1'].should == '1'
      end
    end

    context 'when locks are expiring' do
      it 'republishes' do
        stub_once_on(@operation_klass, :publish_payload_in_redis) { raise }
        expect { Promiscuous.context { PublisherModel.create(:field_1 => '1') } }.to raise_error
        pub = PublisherModel.first

        eventually { Promiscuous::AMQP::Fake.num_messages.should == 1 }

        message = Promiscuous::AMQP::Fake.get_next_message
        payload = JSON.parse(message[:payload])
        dep = payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:1"]
        op = payload['operations'].first
        op['id'].should == pub.id.to_s
        op['operation'].should == 'create'
        op['attributes']['field_1'].should == '1'
      end
    end
  end
end
