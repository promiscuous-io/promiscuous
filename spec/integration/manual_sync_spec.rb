require 'spec_helper'

if ORM.has(:mongoid)
  describe Promiscuous do
    before { use_real_backend }
    before { load_models }
    before { run_subscriber_worker! }

    it 'synchronize records manually' do
      pub_create = PublisherModel.create

      pub_update = nil
      without_promiscuous { pub_update = PublisherModel.first; pub_update.update_attributes(:field_1 => 'hello') }

      # Ensure ordering
      pub_update.promiscuous.sync; pub_create.promiscuous.sync
      eventually { SubscriberModel.first.field_1.should == 'hello' }

      PublisherModel.first.update_attributes(:field_1 => 'ohai')
      eventually { SubscriberModel.first.field_1.should == 'ohai' }
    end

    it 'ignores changes to object if they are not persisted' do
      pub = without_promiscuous { PublisherModel.create(:field_1 => 'hello') }
      pub.field_1 = 'bye'

      expect { pub.promiscuous.sync }.to raise_error
    end
  end
end
