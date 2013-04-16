require 'spec_helper'

describe Promiscuous, 'bootstrapping dependencies' do
  before { use_fake_backend }
  before { load_models }
  before { run_subscriber_worker! }

  context 'during :pass1' do
    before { switch_bootstrap_mode(:pass1) }

    it 'read dependencies are upgraded to write dependencies' do
      pub1 = pub2 = nil
      Promiscuous.context do
        pub1 = PublisherModel.create
      end
      Promiscuous::AMQP::Fake.get_next_payload['dependencies']

      Promiscuous.context do
        pub1.reload
        pub2 = PublisherModel.create
      end
      dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']

      binding.pry
      dep['read'].should == nil
      dep['write'].should == hashed["publisher_models/id/#{pub2.id}:1", "publisher_models/id/#{pub1.id}:1"]
    end
  end

  context 'during :pass2' do
    before { switch_bootstrap_mode(:pass2) }

    it 'read dependencies are not upgraded to write dependencies' do
      pub1 = pub2 = nil
      Promiscuous.context do
        pub1 = PublisherModel.create
      end
      Promiscuous::AMQP::Fake.get_next_payload['dependencies']

      Promiscuous.context do
        pub1.reload
        pub2 = PublisherModel.create
      end
      dep = Promiscuous::AMQP::Fake.get_next_payload['dependencies']

      dep['read'].should  == hashed["publisher_models/id/#{pub1.id}:1"]
      dep['write'].should == hashed["publisher_models/id/#{pub2.id}:1"]
    end
  end
end

describe Promiscuous, 'bootstrapping replication' do
  before { use_real_backend }
  before { Promiscuous::Config.hash_size = 10 }
  before { load_models }
  after  { use_null_backend }

  context 'when there are no races with publishers' do
    it 'bootstraps' do
      Promiscuous.context { 10.times { PublisherModel.create } }

      switch_bootstrap_mode(:pass1)
      Promiscuous::Publisher::Bootstrap::Version.new.bootstrap
      sleep 1

      switch_bootstrap_mode(:pass2)
      Promiscuous::Publisher::Bootstrap::Data.new.bootstrap

      eventually { SubscriberModel.count.should == PublisherModel.count }

      switch_bootstrap_mode(false)
      PublisherModel.all.each { |pub| Promiscuous.context { pub.update_attributes(:field_1 => 'ohai') } }
      eventually { SubscriberModel.each { |sub| sub.field_1.should == 'ohai' } }
    end
  end

  context 'when updates happens after the version bootstrap, but before the document is replicated' do
    it 'bootstraps' do
      Promiscuous.context { 10.times { PublisherModel.create } }

      switch_bootstrap_mode(:pass1)
      Promiscuous::Publisher::Bootstrap::Version.new.bootstrap
      sleep 1

      Promiscuous.context { PublisherModel.first.update_attributes(:field_2 => 'hello') }

      switch_bootstrap_mode(:pass2)
      Promiscuous::Publisher::Bootstrap::Data.new.bootstrap
      eventually { SubscriberModel.count.should == PublisherModel.count - 1 }

      SubscriberModel.first.field_2.should == nil

      switch_bootstrap_mode(:pass3)
      eventually { SubscriberModel.first.field_2.should == 'hello' }

      switch_bootstrap_mode(false)
      eventually { SubscriberModel.first.field_2.should == 'hello' }
      PublisherModel.all.each { |pub| Promiscuous.context { pub.update_attributes(:field_1 => 'ohai') } }
      eventually { SubscriberModel.each { |sub| sub.field_1.should == 'ohai' } }
    end
  end
end

def switch_bootstrap_mode(bootstrap_mode)
  Promiscuous::Config.configure { |config| config.bootstrap = bootstrap_mode }
  if @worker
    @worker.pump.recover # send the nacked message again
  else
    run_subscriber_worker!
  end
end
