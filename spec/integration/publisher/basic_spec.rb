require 'spec_helper'

if ORM.has(:mongoid)
  describe Promiscuous do
    before { use_fake_backend }
    before { load_models }
    before { run_subscriber_worker! }

    context 'when using multi reads' do
      it 'publishes proper dependencies' do
        pub = nil
        Promiscuous.transaction do
          pub = PublisherModel.create
          PublisherModel.first
          PublisherModel.first
          pub.update_attributes(:field_1 => 123)
          PublisherModel.first
          PublisherModel.first
          pub.update_attributes(:field_1 => 456)
        end

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['link'].should  == nil
        dep['read'].should  == nil
        dep['write'].should == ["publisher_models:id:#{pub.id}:1"]

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['link'].should  == "publisher_models:id:#{pub.id}:1"
        dep['read'].should  == ["publisher_models:id:#{pub.id}:1",
                                "publisher_models:id:#{pub.id}:1"]
        dep['write'].should == ["publisher_models:id:#{pub.id}:4"]

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['link'].should  == "publisher_models:id:#{pub.id}:4"
        dep['read'].should  == ["publisher_models:id:#{pub.id}:4",
                                "publisher_models:id:#{pub.id}:4"]
        dep['write'].should == ["publisher_models:id:#{pub.id}:7"]
      end
    end

    context 'when using only reads' do
      it 'publishes proper dependencies' do
        pub = without_promiscuous { PublisherModel.create }
        Promiscuous.transaction(:active => true) do
          PublisherModel.first
        end

        payload = Promiscuous::AMQP::Fake.get_next_payload
        payload['__amqp__'].should == "__promiscuous__/dummy"
        payload['operation'].should == "dummy"
        dep = payload['dependencies']
        dep['link'].should  == nil
        dep['read'].should  == ["publisher_models:id:#{pub.id}:0"]
        dep['write'].should == nil
      end
    end

    context 'when using multi reads/writes on tracked attributes' do
      it 'publishes proper dependencies' do
        PublisherModel.track_dependencies_of :field_1
        PublisherModel.track_dependencies_of :field_2

        pub = nil
        Promiscuous.transaction do
          pub = PublisherModel.create(:field_1 => 123, :field_2 => 456)
          PublisherModel.where(:field_1 => 123).count
          PublisherModel.where(:field_1 => 'blah').count
          PublisherModel.where(:field_1 => 123, :field_2 => 456).count
          PublisherModel.where(:field_1 => 'blah', :field_2 => 456).count
          PublisherModel.where(:field_2 => 456).count
          PublisherModel.where(:field_2 => 'blah').count
          PublisherModel.where(:field_2 => 456).first
          pub.update_attributes(:field_1 => 'blah')
          PublisherModel.where(:field_1 => 123).first
          pub.update_attributes(:field_2 => 'blah')
        end

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['link'].should  == nil
        dep['read'].should  == nil
        dep['write'].should == ["publisher_models:id:#{pub.id}:1",
                                "publisher_models:field_1:123:1",
                                "publisher_models:field_2:456:1"]

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['link'].should  == "publisher_models:id:#{pub.id}:1"
        dep['read'].should  == ["publisher_models:field_1:123:1",
                                "publisher_models:field_1:blah:0",
                                "publisher_models:field_1:123:1",
                                "publisher_models:field_1:blah:0",
                                "publisher_models:field_2:456:1",
                                "publisher_models:field_2:blah:0",
                                "publisher_models:id:#{pub.id}:1"]
        dep['write'].should == ["publisher_models:id:#{pub.id}:3",
                                "publisher_models:field_1:123:4",
                                # FIXME "publisher_models:field_1:blah:3",
                                "publisher_models:field_2:456:3"]

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['link'].should  == "publisher_models:id:#{pub.id}:3"
        dep['read'].should  == nil
        dep['write'].should == ["publisher_models:id:#{pub.id}:4",
                                "publisher_models:field_1:blah:3",
                                "publisher_models:field_2:456:4"]
                                # FIXME "publisher_models:field_2:blah:1",
      end
    end
  end
end
