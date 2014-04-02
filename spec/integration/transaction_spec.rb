require 'spec_helper'

if ORM.has(:transaction)
  describe Promiscuous do
    before { use_real_backend }
    before { load_models }
    before { run_subscriber_worker! }

    context 'when a subscriber operation fails within a transaction' do
      before { Promiscuous::Config.logger.level = Logger::FATAL }
      before do
        SubscriberModel.class_eval do
          after_save { raise if field_1 == 'raise' }
        end

        PublisherModel.transaction do
          PublisherModel.create(:field_1 => '1')
          PublisherModel.create(:field_1 => 'raise')
        end
        PublisherModel.create(:field_1 => '2')
      end

      it 'does not replicate any of the opertations that were part of the transaction' do
        eventually do
          SubscriberModel.first.field_1.should == '2'
          SubscriberModel.count.should == 1
        end
      end
    end

    context 'with multiple operations within a transaction' do
      before do
        pub = PublisherModel.create(:field_1 => '1')
        pub.update_attributes(:field_1 => '2')

        PublisherModel.transaction do
          PublisherModel.create(:field_1 => '1')
          pub.update_attributes(:field_1 => '3')
        end
      end

      it 'consistency is maintained' do
        eventually do
          SubscriberModel.where(:field_1 => '3').count.should == 1
        end
      end
    end
  end
end
