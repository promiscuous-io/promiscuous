require 'spec_helper'

describe Promiscuous do
  before do 
    $error = false
    use_real_backend { |config| config.error_notifier = proc { $error = true } }
  end
  before { load_models }
  before { run_subscriber_worker! }

  context 'with a published model without a subscription' do
    before do
    end
    it "doesn't throw an error" do
      PublisherModelWithoutSubscriber.create(:field_1 => "field1")

      sleep 1

      $error.should == false
    end
  end
end
