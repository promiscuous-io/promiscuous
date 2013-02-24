require 'spec_helper'

if ORM.has(:mongoid)
  describe Promiscuous do
    before { use_real_backend }
    before { load_models }
    before { record_callbacks(SubscriberModel) }

    before { run_subscriber_worker! }

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
          subscribe(:from => '*/publisher') { field :field }
          field :inc_by_one
          before_update { inc(:inc_by_one, 1) if field == field_was + 1 }
        end

        run_subscriber_worker!
      end

      it 'stays ordered' do
        pub = Promiscuous.transaction { Publisher.create(:field => 0) }
        10.times.map { Thread.new { Promiscuous.transaction { 10.times { pub.inc(:field, 1) } } } }.each(&:join)
        eventually :timeout => 10.seconds do
          Subscriber.first.field.should == 100
          Subscriber.first.inc_by_one.should == 100
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
  end
end
