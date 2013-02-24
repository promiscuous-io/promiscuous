require 'spec_helper'

describe Promiscuous do
  before { use_real_backend }
  before { load_models }
  before { run_subscriber_worker! }

  context 'when doing a write in a transaction' do
    it 'learns' do
      @run_count = 0
      Promiscuous.transaction('test') do
        PublisherModel.first
        @run_count += 1
        PublisherModel.create
      end

      eventually { SubscriberModel.count.should == 1 }

      Promiscuous.transaction('test') do
        PublisherModel.first
        @run_count += 1
        PublisherModel.create
      end

      eventually { SubscriberModel.count.should == 2 }

      @run_count.should == 3
    end

    it 'can switch back to the optimistic mode' do
      Promiscuous.transaction('test') do
        PublisherModel.first
        PublisherModel.create
      end

      eventually { SubscriberModel.count.should == 1 }

      20.times do
        Promiscuous.transaction('test') do
          PublisherModel.first
        end
      end

      @run_count = 0
      Promiscuous.transaction('test') do
        PublisherModel.first
        @run_count += 1
        PublisherModel.create
      end

      @run_count.should == 2
    end

    it 'throws exception if closed' do
      Promiscuous.transaction('test') do
        PublisherModel.first
        Promiscuous.close_current_transaction
        expect { PublisherModel.create }.to raise_error(Promiscuous::Error::ClosedTransaction)
      end
    end

    it 'throws exception when non idempotent' do
      expect do
        @do_write = true
        Promiscuous.transaction('test') do
          if @do_write
            @do_write = false
            PublisherModel.create
          end
        end
      end.to raise_error(Promiscuous::Error::IdempotentViolation)
    end
  end
end
