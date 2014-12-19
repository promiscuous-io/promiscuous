require 'spec_helper'

describe Promiscuous do
  before { use_real_backend { |config| config.publisher_lock_expiration = 10
                                       config.publisher_lock_timeout    = 5 } }
  before { load_models }
  before { record_callbacks(SubscriberModel) }

  before { run_subscriber_worker! }

  context 'when doing a blank update' do
    it 'passes through' do
      pub = PublisherModel.create(:field_1 => '1')
      eventually { SubscriberModel.first.should_not == nil }
      ORM.purge!
      expect { pub.update_attributes(:field_1 => '2') }.to_not raise_error
    end
  end

  context 'when doing a blank destroy' do
    it 'passes through' do
      pub = PublisherModel.create(:field_1 => '1')
      eventually { SubscriberModel.first.should_not == nil }
      ORM.purge!
      expect { pub.destroy }.to_not raise_error
    end
  end

  context 'when doing multi updates' do
    it 'fails immediately' do
      expect { PublisherModel.update_all(:field_1 => '1') }.to raise_error
    end
  end

  context 'when doing multi delete' do
    it 'fails immediately' do
      expect { PublisherModel.delete_all(:field_1 => '1') }.to raise_error
    end
  end

  if ORM.has(:mongoid)
    context 'when doing parallel increments' do
      before do
        define_constant :Publisher do
          include Mongoid::Document
          include Promiscuous::Publisher
          publish { field :field }
        end

        define_constant :Subscriber do
          include Mongoid::Document
          include Promiscuous::Subscriber
          subscribe(:as => :Publisher) { field :field }
        end

        run_subscriber_worker!
      end

      it 'stays ordered' do
        pubs = 3.times.map { Publisher.create(:field => 0) }
        pubs.map do |pub|
          10.times.map { Thread.new { 10.times { pub.inc(:field, 1) } } }
        end.flatten.each(&:join)

        eventually :timeout => 10.seconds do
          Subscriber.count.should == 3
          Subscriber.all.each do |sub|
            sub.field.should == 100
          end
        end
      end
    end
  end

  context 'when subscribing to a subset of models' do
    it 'replicates' do
      PublisherModel.create
      PublisherModelOther.create
      PublisherModel.create

      eventually do
        SubscriberModel.num_saves.should == 2
      end
    end
  end

  context 'when the publisher fails' do
    it 'replicates' do
      pub1 = PublisherModel.create(:field_1 => '1')
      expect do
        PublisherModel.create({:id => pub1.id, :field_1 => '2'}, :without_protection => true)
      end.to raise_error
      PublisherModel.create(:field_1 => '3')

      eventually do
        SubscriberModel.count.should == 2
      end
    end
  end
end
