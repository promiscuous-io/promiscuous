require 'spec_helper'
require 'replicable/worker'

describe Replicable do
  before { load_models }

  let!(:error_handler) { proc { |exception| @error_handler_called_with = exception } }
  before { use_real_amqp(:error_handler => error_handler, :logger_level => Logger::FATAL) }

  context 'when replicating the update of a model that fails' do
    before do
      define_constant('Publisher', Replicable::Publisher::Mongoid) do
        publish :to => 'crowdtap/publisher_model',
          :class => PublisherModel,
          :attributes => [:field_1, :field_2, :field_3]
      end

      define_constant('Subscriber', Replicable::Subscriber::Mongoid) do
        subscribe :from => 'crowdtap/publisher_model',
          :class => SubscriberModel,
          :attributes => [:field_1, :field_2, :field_3]
      end
    end

    before { Replicable::Worker.run }
    before { SubscriberModel.class_eval { validates_format_of :field_1, :without => /updated/ } }

    it 'calls the error_handler with an exception' do
      pub = PublisherModel.create
      pub.update_attributes(:field_1 => 'updated')
      eventually { @error_handler_called_with.should be_a(Exception) }
    end

    it 'stops processing anything' do
      pub = PublisherModel.create
      pub.update_attributes!(:field_1 => 'updated')
      pub.update_attributes!(:field_1 => 'another_update')

      eventually { @error_handler_called_with.should be_a(Exception) }
      EM::Synchrony.sleep 0.5
      eventually { SubscriberModel.find(pub.id).field_1.should_not == 'another_update' }
    end
  end

  context 'when subscribing to non published fields' do
    before do
      define_constant('Publisher', Replicable::Publisher::Mongoid) do
        publish :to => 'crowdtap/publisher_model',
          :class => PublisherModel,
          :attributes => [:field_1, :field_2]
      end

      define_constant('Subscriber', Replicable::Subscriber::Mongoid) do
        subscribe :from => 'crowdtap/publisher_model',
          :class => SubscriberModel,
          :attributes => [:field_1, :field_2, :field_3]
      end
    end

    before { Replicable::Worker.run }

    it 'calls the error_handler with an exception' do
      PublisherModel.create
      eventually { @error_handler_called_with.should be_a(Exception) }
    end
  end

  after do
    Replicable::AMQP.close
    Replicable::Subscriber::AMQP.subscribers.clear
  end
end
