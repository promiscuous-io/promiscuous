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

    context 'when using each' do
      it 'publishes proper dependencies' do
        PublisherModel.track_dependencies_of :field_1

        pub1 = pub2 = nil
        Promiscuous.transaction do
          pub1 = PublisherModel.create(:field_1 => 123)
          pub2 = PublisherModel.create(:field_1 => 123)
          PublisherModel.where(:field_1 => 123).each.to_a
          pub1.update_attributes(:field_2 => 456)
        end

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['link'].should  == nil
        dep['read'].should  == nil
        dep['write'].should == ["publisher_models:id:#{pub1.id}:1",
                                "publisher_models:field_1:123:1"]

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['link'].should  == "publisher_models:id:#{pub1.id}:1"
        dep['read'].should  == nil
        dep['write'].should == ["publisher_models:id:#{pub2.id}:1",
                                "publisher_models:field_1:123:2"]

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['link'].should  == "publisher_models:id:#{pub2.id}:1"
        dep['read'].should  == ["publisher_models:field_1:123:2"]
        dep['write'].should == ["publisher_models:id:#{pub1.id}:2",
                                "publisher_models:field_1:123:4"]
      end
    end

    context 'when using a uniqueness validator' do
      it 'skips the query' do
        PublisherModel.validates_uniqueness_of :field_1

        pub = nil
        Promiscuous.transaction do
          pub = PublisherModel.create(:field => 123)
        end

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['link'].should  == nil
        dep['read'].should  == nil
        dep['write'].should == ["publisher_models:id:#{pub.id}:1"]
      end
    end

    context 'when using limit(1).each' do
      it 'skips the query' do
        pub1 = pub2 = nil
        Promiscuous.transaction do
          pub1 = PublisherModel.create(:field_1 => 123)
          PublisherModel.all.limit(1).each do |pub|
            pub.id.should      == pub1.id
            pub.field_1.should == pub1.field_1
          end
          pub2 = PublisherModel.create(:field_1 => 123)
        end

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['link'].should  == nil
        dep['read'].should  == nil
        dep['write'].should == ["publisher_models:id:#{pub1.id}:1"]

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['link'].should  == "publisher_models:id:#{pub1.id}:1"
        dep['read'].should  == ["publisher_models:id:#{pub1.id}:1"]
        dep['write'].should == ["publisher_models:id:#{pub2.id}:1"]
      end
    end

    context 'when using nested transactions' do
      it 'publishes proper dependencies' do
        pub1 = without_promiscuous { PublisherModel.create }
        pub2 = pub3 = pub4 = nil
        @pre_run_count1 = @pre_run_count2 = @pre_run_count3 = 0
        @post_run_count1 = @post_run_count2 = @post_run_count3 = 0

        Promiscuous.transaction(:first) do
          @pre_run_count1 += 1
          PublisherModel.first
          Promiscuous.transaction(:second) do
            @pre_run_count2 += 1
            Promiscuous.transaction(:third) do
              @pre_run_count3 += 1
              pub2 = PublisherModel.create
              @post_run_count3 += 1
            end
            PublisherModel.first
            pub3 = PublisherModel.create
            @post_run_count2 += 1
          end
          pub4 = PublisherModel.create
          @post_run_count1 += 1
        end

        @pre_run_count1.should == 2
        @pre_run_count2.should == 2
        @pre_run_count3.should == 2
        @post_run_count1.should == 1
        @post_run_count2.should == 1
        @post_run_count3.should == 1

        payload = Promiscuous::AMQP::Fake.get_next_payload
        payload['transaction'].should == 'third'
        dep = payload['dependencies']
        dep['link'].should  == nil
        dep['read'].should  == nil
        dep['write'].should == ["publisher_models:id:#{pub2.id}:1"]

        payload = Promiscuous::AMQP::Fake.get_next_payload
        payload['transaction'].should == 'second'
        dep = payload['dependencies']
        dep['link'].should  == "publisher_models:id:#{pub2.id}:1"
        dep['read'].should  == ["publisher_models:id:#{pub1.id}:0"]
        dep['write'].should == ["publisher_models:id:#{pub3.id}:1"]

        payload = Promiscuous::AMQP::Fake.get_next_payload
        payload['transaction'].should == 'first'
        dep = payload['dependencies']
        dep['link'].should  == "publisher_models:id:#{pub3.id}:1"
        dep['read'].should  == ["publisher_models:id:#{pub1.id}:0"]
        dep['write'].should == ["publisher_models:id:#{pub4.id}:1"]

        Promiscuous::AMQP::Fake.get_next_message.should == nil
      end
    end

    context 'when used with without read dependencies' do
      it "doens't track reads" do
        pub1 = pub2 = nil
        Promiscuous.transaction :without_read_dependencies => true do
          pub1 = PublisherModel.create
          PublisherModel.first
          pub2 = PublisherModel.create
          PublisherModel.first
        end

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['link'].should  == nil
        dep['read'].should  == nil
        dep['write'].should == ["publisher_models:id:#{pub1.id}:1"]

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['link'].should  == "publisher_models:id:#{pub1.id}:1"
        dep['read'].should  == nil
        dep['write'].should == ["publisher_models:id:#{pub2.id}:1"]
      end
    end

    context 'when updating a field that is not published' do
      it "doesn't track the write" do
        PublisherModel.field :not_published

        pub = nil
        Promiscuous.transaction do
          pub = PublisherModel.create
          pub.update_attributes(:not_published => 'hello')
          pub.update_attributes(:field_1 => 'ohai')
        end

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['link'].should  == nil
        dep['read'].should  == nil
        dep['write'].should == ["publisher_models:id:#{pub.id}:1"]

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['link'].should  == "publisher_models:id:#{pub.id}:1"
        dep['read'].should  == nil
        dep['write'].should == ["publisher_models:id:#{pub.id}:2"]

        Promiscuous::AMQP::Fake.get_next_message.should == nil
      end
    end

    context 'when using map reduce' do
      it 'track the read' do
        PublisherModel.track_dependencies_of :field_1
        without_promiscuous do
          PublisherModel.create(:field_1 => 123)
          PublisherModel.create(:field_1 => 123)
        end
        Promiscuous.transaction :force => true do
          PublisherModel.where(:field_1 => 123).sum(:field_2)
        end

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['link'].should  == nil
        # Mongoid does an extra count.
        dep['read'].should  == ["publisher_models:field_1:123:0",
                                "publisher_models:field_1:123:0"]
        dep['write'].should == nil
      end
    end

    context 'when using one_by_one.each' do
      it 'track the reads one by one' do
        pub1 = pub2 = nil
        without_promiscuous do
          pub1 = PublisherModel.create(:field_1 => 123)
          pub2 = PublisherModel.create(:field_1 => 123)
        end
        Promiscuous.transaction :force => true do
          expect do
            PublisherModel.all.without_read_dependencies.where(:field_1 => 123).each do |p|
              p.reload
            end
          end.to_not raise_error
        end

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['link'].should  == nil
        dep['read'].should  == ["publisher_models:id:#{pub1.id}:0",
                                "publisher_models:id:#{pub2.id}:0"]
        dep['write'].should == nil
      end
    end
  end
end
