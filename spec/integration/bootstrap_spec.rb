require 'spec_helper'

describe Promiscuous, 'bootstrapping' do
  before { use_real_backend }
  before { Promiscuous::Config.hash_size = 10 }
  before { load_models }
  after  { use_null_backend }

  def switch_bootstrap_mode(bootstrap_mode)
    Promiscuous::Config.bootstrap = bootstrap_mode
    if @worker
      @worker.pump.recover # send the nacked message again
    else
      run_subscriber_worker!
    end
  end

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
