require 'spec_helper'

if ORM.has(:mongoid)
  describe Promiscuous do
    before { use_real_backend }
    before { load_models }
    before { run_subscriber_worker! }

    it "can reset verions by flusing redis and incrementing the generation number" do
      Promiscuous::Config.generation = nil

      pub = pub = PublisherModel.create(:field_1 => '1')
      eventually { SubscriberModel.first.field_1.should == '1' }

      Promiscuous::Redis.connection.flushdb
      Promiscuous::Config.generation = 1

      pub.update_attributes(:field_1 => '2')
      eventually { SubscriberModel.first.field_1.should == '2' }

      Promiscuous::Redis.connection.flushdb
      Promiscuous::Config.generation = 2

      pub.update_attributes(:field_1 => '3')
      eventually { SubscriberModel.first.field_1.should == '3' }
    end
  end
end
