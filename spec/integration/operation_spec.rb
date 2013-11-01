require 'spec_helper'

  describe Promiscuous do
    before { use_fake_backend }
    before { load_models }
    before { run_subscriber_worker! }

    context 'when using multi reads' do
      it 'publishes proper dependencies' do
        pub = nil
        Promiscuous.context do
          pub = PublisherModel.create
          PublisherModel.first
          PublisherModel.first
          pub.update_attributes(:field_1 => 123)
          PublisherModel.first
          PublisherModel.first
          pub.update_attributes(:field_1 => 456)
        end

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:1"]

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:2"]

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:3"]
      end
    end

    context 'when using only reads' do
      it 'publishes proper dependencies' do
        without_promiscuous { PublisherModel.create }
        Promiscuous.context { PublisherModel.first }
        Promiscuous::AMQP::Fake.get_next_message.should == nil
      end
    end

    context 'when using only writes that hits' do
      it 'publishes proper dependencies' do
        pub = Promiscuous.context { PublisherModel.create(:field_1 => '1') }

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:1"]
      end
    end

    context 'when using only writes that misses' do
      it 'publishes proper dependencies' do
        Promiscuous.context do
          if ORM.has(:transaction)
            PublisherModel.transaction do
              PublisherModel.where(:id => 123).update_all(:field_1 => '1')
            end
          else
            PublisherModel.where(:id => 123).update(:field_1 => '1')
          end
        end

        Promiscuous::AMQP::Fake.get_next_message.should == nil
      end
    end

    context 'when using multi reads/writes on tracked attributes' do
      it 'publishes proper dependencies', :pending => ORM.has(:active_record) && 'FIXMES' do
        PublisherModel.track_dependencies_of :field_1
        PublisherModel.track_dependencies_of :field_2

        pub = nil
        Promiscuous.context do
          pub = PublisherModel.create(:field_1 => '123', :field_2 => '456')
          PublisherModel.where(:field_1 => '123').count
          PublisherModel.where(:field_1 => 'blah').count
          PublisherModel.where(:field_1 => '123', :field_2 => '456').count
          PublisherModel.where(:field_1 => 'blah', :field_2 => '456').count
          PublisherModel.where(:field_2 => '456').count
          PublisherModel.where(:field_2 => 'blah').count
          PublisherModel.where(:field_2 => '456').first
          pub.update_attributes(:field_1 => 'blah')
          PublisherModel.where(:field_1 => '123').first
          pub.update_attributes(:field_2 => 'blah')
        end

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should =~ hashed["publisher_models/id/#{pub.id}:1",
                                      "publisher_models/field_1/123:1",
                                      "publisher_models/field_2/456:1"]

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['read'].should  =~ hashed["publisher_models/field_1/blah:0",
                                      "publisher_models/field_2/blah:0"]
        dep['write'].should =~ hashed["publisher_models/id/#{pub.id}:2",
                                      "publisher_models/field_1/123:2",
                                      # FIXME "publisher_models/field_1/blah:3",
                                      "publisher_models/field_2/456:2"]

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        # We include the set dependency because we want to track the fact
        # that that document was not there.
        dep['read'].should  == hashed["publisher_models/field_1/123:2"]
        dep['write'].should =~ hashed["publisher_models/id/#{pub.id}:3",
                                      "publisher_models/field_1/blah:2",
                                      "publisher_models/field_2/456:3"]
                                      # FIXME "publisher_models/field_2/blah:1",
      end
    end

    context 'when using each' do
      it 'publishes proper dependencies' do
        PublisherModel.track_dependencies_of :field_1

        pub1 = pub2 = nil
        Promiscuous.context do
          pub1 = PublisherModel.create(:field_1 => '123')
          pub2 = PublisherModel.create(:field_1 => '123')
          PublisherModel.where(:field_1 => '123').each.to_a
          pub1.update_attributes(:field_2 => '456')
        end

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['read'].should  == nil

        dep['write'].should == hashed["publisher_models/id/#{pub1.id}:1",
                                      "publisher_models/field_1/123:1"]

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['read'].should  == hashed["publisher_models/id/#{pub1.id}:1"]
        dep['write'].should == hashed["publisher_models/id/#{pub2.id}:1",
                                      "publisher_models/field_1/123:2"]

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['read'].should  == hashed["publisher_models/id/#{pub2.id}:1"]
        dep['write'].should == hashed["publisher_models/id/#{pub1.id}:3",
                                      "publisher_models/field_1/123:3"]
      end
    end

    context 'when using a uniqueness validator' do
      it 'skips the query' do
        PublisherModel.validates_uniqueness_of :field_1

        pub = nil
        Promiscuous.context do
          pub = PublisherModel.create(:field_1 => '123')
        end

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:1"]
      end
    end

    context 'when using limit(1).each' do
      it 'skips the query' do
        pub1 = pub2 = nil
        Promiscuous.context do
          pub1 = PublisherModel.create(:field_1 => '123')
          PublisherModel.where({}).limit(1).each do |pub|
            pub.id.should      == pub1.id
            pub.field_1.should == pub1.field_1
          end
          pub2 = PublisherModel.create(:field_1 => '123')
        end

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub1.id}:1"]

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['read'].should  == hashed["publisher_models/id/#{pub1.id}:1"]
        dep['write'].should == hashed["publisher_models/id/#{pub2.id}:1"]
      end
    end

    context 'when updating a field that is not published' do
      it "doesn't track the write" do
        pub = nil
        Promiscuous.context do
          pub = PublisherModel.create
          pub.update_attributes(:publisher_id => 123)
          pub.update_attributes(:field_1 => 'ohai')
        end

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:1"]

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['read'].should  == nil
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:2"]

        Promiscuous::AMQP::Fake.get_next_message.should == nil
      end
    end

    context 'when using sum' do
      it 'track the read' do
        PublisherModel.track_dependencies_of :field_1
        without_promiscuous do
          PublisherModel.create(:field_1 => '123')
          PublisherModel.create(:field_1 => '123')
        end
        pub = nil
        Promiscuous.context do
          # sum on publisher_id, too lazy to change field_1 type to numeric
          PublisherModel.where(:field_1 => '123').sum(:publisher_id)
          pub = PublisherModel.create(:field_1 => '456')
        end

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['read'].should  == hashed["publisher_models/field_1/123:0"]
        dep['write'].should == hashed["publisher_models/id/#{pub.id}:1",
                                      "publisher_models/field_1/456:1"]
      end
    end

    context 'when using without_promiscuous.each' do
      context 'when tracking the set' do
        before { PublisherModel.track_dependencies_of :field_1 }

        it 'track the reads one by one if the set is not tracked' do
          pub1 = pub2 = pub3 = pub4 = nil
          without_promiscuous do
            pub1 = PublisherModel.create(:field_1 => '123')
            pub2 = PublisherModel.create(:field_1 => '123')
            pub3 = PublisherModel.create(:field_1 => '123')
          end
          Promiscuous.context do
            q = PublisherModel.where(:field_1 => '123')
            q = q.batch_size(2) if ORM.has(:mongoid)
            q.to_a
            pub4 = PublisherModel.create(:field_2 => '456')
          end

          dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
          dep['read'].should  =~ hashed["publisher_models/field_1/123:0"]
          dep['write'].should == hashed["publisher_models/id/#{pub4.id}:1"]
        end
      end

      context 'when the set is not tracked' do
        it 'track the reads one by one if the set is not tracked' do
          pub1 = pub2 = pub3 = pub4 = nil
          without_promiscuous do
            pub1 = PublisherModel.create(:field_1 => '123')
            pub2 = PublisherModel.create(:field_1 => '123')
            pub3 = PublisherModel.create(:field_1 => '123')
          end
          Promiscuous.context do
            q = PublisherModel.where(:field_1 => '123')
            q = q.batch_size(2) if ORM.has(:mongoid)
            q.to_a
            pub4 = PublisherModel.create(:field_2 => '456')
          end

          dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
          dep['read'].should  =~ hashed["publisher_models/id/#{pub1.id}:0",
                                        "publisher_models/id/#{pub3.id}:0",
                                        "publisher_models/id/#{pub2.id}:0"]
          dep['write'].should == hashed["publisher_models/id/#{pub4.id}:1"]
        end
      end
    end

    context 'when using hashing' do
      before { Promiscuous::Config.hash_size = 1 }
      before { PublisherModel.track_dependencies_of :field_1 }

      it 'collides properly' do
        pub1 = pub2 = pub3 = nil
        Promiscuous.context do
          pub1 = PublisherModel.create(:field_1 => '123')
          pub2 = PublisherModel.create(:field_1 => '456')
          PublisherModel.first
          PublisherModel.where(:field_1 => '456').count
          pub3 = PublisherModel.create(:field_1 => '456')
        end

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['read'].should == nil
        dep['write'].should == ["0:1"]

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['read'].should == nil
        dep['write'].should == ["0:2"]

        dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']
        dep['read'].should == nil
        dep['write'].should == ["0:3"]
      end
    end
  end
