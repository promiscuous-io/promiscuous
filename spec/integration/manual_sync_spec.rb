require 'spec_helper'

if ORM.has(:mongoid)
  describe Promiscuous do
    before { use_real_backend }
    before { load_models }
    before { run_subscriber_worker! }

    it 'synchronize records manually' do
      pub = Promiscuous.context { PublisherModel.create }

      without_promiscuous { PublisherModel.first.update_attributes(:field_1 => 'hello') }

      # no reload, that would incorrect

      Promiscuous.context { pub.promiscuous.sync }
      eventually { SubscriberModel.first.field_1 == 'hello' }

      Promiscuous.context { PublisherModel.first.update_attributes(:field_1 => 'ohai') }
      eventually { SubscriberModel.first.field_1 == 'ohai' }
    end
  end
end
