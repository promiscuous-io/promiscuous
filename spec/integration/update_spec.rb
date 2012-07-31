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

      replicate :app_name => 'crowdtap'
    end

    define_constant(:subscriber_model) do
      include Mongoid::Document
      include Replicable::Subscriber

      field :field_1
      field :field_2
      field :field_3

      replicate :from => 'crowdtap',
                :class_name => 'publisher_model',
                :fields => [:field_1, :field_2, :field_3]
    end
  end

  before do
    Replicable::AMQP.configure(:backend => :rubyamqp, :app => 'sniper',
                               :queue_options => {:auto_delete => true})
    Replicable::Subscriber::Worker.run
  end

  context 'when replicating the update of a model' do
    let!(:instance) { PublisherModel.create }

    it 'updates the model' do
      instance.update_attributes(:field_1 => 'updated')
      eventually { SubscriberModel.find(instance.id).field_1.should == 'updated' }
    end
  end

  context 'when replicating the update of a model that fails' do
    let!(:error_handler) { proc { |exception| @error_handler_called_with = exception } }

    before do
      Replicable::AMQP.configure(:backend => :rubyamqp, :app => 'sniper',
                                 :queue_options => {:auto_delete => true},
                                 :logger_level => 4,
                                 :error_handler => error_handler)

    Replicable::Subscriber::Worker.run
    end

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
