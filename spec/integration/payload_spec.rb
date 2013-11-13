require 'spec_helper'

describe Promiscuous do
  before { use_fake_backend }
  before { load_models; load_mocks; load_ephemerals }
  before { run_subscriber_worker! }

  it "includes the hosname in the payload" do
    Socket.stubs(:gethostname => 'example.com')

    Promiscuous.context { PublisherModel.create(:field_1 => '1') }

    Promiscuous::AMQP::Fake.get_next_payload['host'].should == 'example.com'
  end

  describe "includes the current_user in the payload" do
    context "with a publisher" do
      it "the second attribute that is passed to the context is used" do
        user = without_promiscuous { PublisherModel.create }

        Promiscuous.context('test', :current_user => user) do
          PublisherModel.create(:field_1 => '1')
        end

        Promiscuous::AMQP::Fake.get_next_payload['current_user_id'].to_s.should == user.id.to_s
      end
    end
    context "with a mock and without a context" do
      it "does not raise an execption" do
        expect do
          without_promiscuous { MockModel.create(:field_1 => '1') }
        end.to_not raise_error
      end
    end
  end
end
