require 'spec_helper'

describe Promiscuous do
  before { load_models }

  let!(:error_notifier) { proc { |exception| @error_notifier_called_with = exception } }
  before { use_real_backend(:error_notifier => error_notifier, :logger_level => Logger::FATAL) }

  context 'when replicating the update of a model that fails' do
    before { run_subscriber_worker! }

    context 'on the subscriber side' do
      before { SubscriberModel.class_eval { validates_format_of :field_1, :without => /death/ } }

      it 'calls the error_notifier with an exception' do
        Promiscuous.transaction do
          pub = PublisherModel.create
          pub.update_attributes(:field_1 => 'death')
        end
        eventually do
          @error_notifier_called_with.should be_a(Promiscuous::Error::Subscriber)
          @error_notifier_called_with.payload.should =~ /death/
        end
      end
    end
  end

  context 'when subscribing to non published fields' do
    before { SubscriberModel.class_eval { subscribe :hello } }
    before { run_subscriber_worker! }

    it 'calls the error_notifier with an exception' do
      Promiscuous.transaction { PublisherModel.create }
      eventually { @error_notifier_called_with.should be_a(Exception) }
    end
  end
end
