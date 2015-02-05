require 'spec_helper'

describe Promiscuous do
  before { use_fake_backend }
  before { load_models; load_mocks; load_ephemerals }

  it "includes the hosname in the payload" do
    Socket.stubs(:gethostname => 'example.com')

    PublisherModel.create(:field_1 => '1')

    Promiscuous::Backend::Fake.get_next_payload['host'].should == 'example.com'
  end

  describe "includes the current_user in the payload" do
    context "with a publisher" do
      it "the second attribute that is passed to the context is used" do
        user = PublisherModel.create
        Promiscuous.context.current_user = user
        Promiscuous::Backend::Fake.get_next_payload

        PublisherModel.create(:field_1 => '1')

        Promiscuous::Backend::Fake.get_next_payload['current_user_id'].to_s.should == user.id.to_s
      end
    end
  end
end
