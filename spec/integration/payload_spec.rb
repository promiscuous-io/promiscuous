require 'spec_helper'

describe Promiscuous do
  before { use_fake_backend }
  before { load_models }
  before { run_subscriber_worker! }

  it "includes the hosname in the payload" do
    Socket.stubs(:gethostname => 'example.com')

    Promiscuous.context { PublisherModel.create(:field_1 => '1') }

    Promiscuous::AMQP::Fake.get_next_payload['from_host'].should == 'example.com'
  end

  it "includes the current_user in the payload" do
    Promiscuous.context('test', 'ABC') do
      PublisherModel.create(:field_1 => '1')
    end

    Promiscuous::AMQP::Fake.get_next_payload['current_user_id'].should == 'ABC'
  end
end
