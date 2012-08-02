require 'spec_helper'
require 'replicable/subscriber/worker'

describe Replicable do
  before do
    define_constant(:publisher_model) do
      include Mongoid::Document
      include Replicable::Publisher

      field :field_1
      field :field_2
      field :field_3
      field :field_4

      replicate :app_name => 'test_publisher'
    end

    define_constant(:subscriber_model) do
      include Mongoid::Document
      include Replicable::Subscriber

      replicate :from => 'test_publisher', :class_name => 'publisher_model' do
        field :field_1
        field :field_2
        field :field_3
      end

      field :field_4, :default => 'not_updated'
    end
  end

  before { use_real_amqp }
  before { Replicable::Subscriber::Worker.run }

  context 'when replicating the update of a model' do
    let!(:instance) { PublisherModel.create }

    it 'updates the model' do
      instance.update_attributes(:field_1 => 'updated')
      eventually { SubscriberModel.find(instance.id).field_1.should == 'updated' }
    end

    it 'does not update fields that are not subscribed to' do
      instance.update_attributes(:field_1 => 'updated', :field_4 => 'updated')
      eventually do
        sub = SubscriberModel.find(instance.id)
        sub.field_1.should == 'updated'
        sub.field_4.should == 'not_updated'
      end
    end
  end

  context 'when replicating the update of a model that fails' do
    let!(:error_handler) { proc { |exception| @error_handler_called_with = exception } }

    before { use_real_amqp(:error_handler => error_handler, :logger_level => Logger::FATAL) }
    before { Replicable::Subscriber::Worker.run }
    before { SubscriberModel.class_eval { validates_format_of :field_1, :without => /updated/ } }

    let!(:instance) { PublisherModel.create }

    it 'calls the error_handler with an exception' do
      instance.update_attributes(:field_1 => 'updated')
      eventually { @error_handler_called_with.should be_a(Exception) }
    end

    it 'stops processing anything' do
      instance.update_attributes(:field_1 => 'updated')
      instance.update_attributes(:field_1 => 'another_update')

      eventually { @error_handler_called_with.should be_a(Exception) }
      EM::Synchrony.sleep 0.5
      eventually { SubscriberModel.find(instance.id).field_1.should_not == 'another_update' }
    end
  end

  after do
    Replicable::AMQP.close
    Replicable::Subscriber.subscriptions.clear
  end
end
