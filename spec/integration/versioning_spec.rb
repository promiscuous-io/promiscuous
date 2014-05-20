require 'spec_helper'

  describe Promiscuous do
    before { use_fake_backend }
    before { load_models }
    before { run_subscriber_worker! }

    context 'when using only writes that hits' do
      it 'publishes proper dependencies' do
        pub = PublisherModel.create(:field_1 => '1')

        op = Promiscuous::AMQP::Fake.get_next_payload['operations'].first
        op['version'].should == 1
      end
    end

    context 'when using only writes that misses' do
      it 'publishes proper dependencies' do
        if ORM.has(:transaction)
          PublisherModel.transaction do
            PublisherModel.where(:id => 123).update_all(:field_1 => '1')
          end
        else
          PublisherModel.where(:id => 123).update(:field_1 => '1')
        end

        Promiscuous::AMQP::Fake.get_next_message.should == nil
      end
    end

    context 'when updating a field that is not published' do
      it "doesn't track the write" do
        pub = PublisherModel.create
        pub.update_attributes(:publisher_id => 123)
        pub.update_attributes(:field_1 => 'ohai')

        op = Promiscuous::AMQP::Fake.get_next_payload['operations'].first
        op['version'].should == 1

        op = Promiscuous::AMQP::Fake.get_next_payload['operations'].first
        op['version'].should == 2

        Promiscuous::AMQP::Fake.get_next_message.should == nil
      end
    end

    context 'when updating a model that is not published' do
      before { 10.times { |i| SubscriberModel.create(:field_1 => "field#{i}") } }

      it 'can update_all' do
        SubscriberModel.update_all(:field_1 => 'updated')

        Promiscuous::AMQP::Fake.get_next_payload.should == nil
        SubscriberModel.all.each { |doc| doc.field_1.should == 'updated' }
      end
    end
  end
