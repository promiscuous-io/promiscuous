require 'spec_helper'

describe Promiscuous do
  before { use_real_backend }
  before { load_models }
  before { run_subscriber_worker! }

  it 'synchronize records manually' do
    pub_create = PublisherModel.create

    pub_update = nil
    without_promiscuous { pub_update = PublisherModel.first; pub_update.update_attributes(:field_1 => 'hello') }

    # Ensure ordering
    PublisherModel.find(pub_update.id).promiscuous.sync(Promiscuous::Config.app); PublisherModel.find(pub_create.id).reload.promiscuous.sync(Promiscuous::Config.app)

    eventually { SubscriberModel.first.field_1.should == 'hello' }

    PublisherModel.first.update_attributes(:field_1 => 'ohai')

    eventually { SubscriberModel.first.field_1.should == 'ohai' }
  end

  it 'prevents syncing an object with changes' do
    pub = without_promiscuous { PublisherModel.create(:field_1 => 'hello') }
    pub.field_1 = 'bye'

    expect { pub.promiscuous.sync }.to raise_error
  end

  it 'prevents syncing an object that was persisted' do
    pub = without_promiscuous { PublisherModel.create(:field_1 => 'hello') }

    expect { pub.promiscuous.sync }.to raise_error
  end

  it "doesn't consume a sync not targeted to the current app" do
    pub_create = PublisherModel.create

    without_promiscuous { pub_create.update_attributes(:field_1 => 'hello') }

    PublisherModel.find(pub_create.id).promiscuous.sync('xxx')

    sleep 0.1

    SubscriberModel.first.field_1.should_not == 'hello'
  end

  it "can sync to all subscribers" do
    pub_create = PublisherModel.create

    without_promiscuous { pub_create.update_attributes(:field_1 => 'hello') }

    PublisherModel.find(pub_create.id).promiscuous.sync(Promiscuous::Config.sync_all_routing)

    eventually { SubscriberModel.first.field_1.should == 'hello' }
  end
end
