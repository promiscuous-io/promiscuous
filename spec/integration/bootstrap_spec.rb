require 'spec_helper'

describe Promiscuous, 'bootstrapping' do
  before { use_real_backend }
  before { Promiscuous::Config.hash_size = 10 }
  before { load_models }
  after  { use_null_backend }

  def switch_mode(options={})
    @worker.try(:stop)
    @worker = nil
    reconfigure_backend do |config|
      config.bootstrap = options[:bootstrap]
      config.hash_size = 10
    end
    @worker = Promiscuous::Subscriber::Worker.new
    @worker.start
  end

  context 'when there are no races with publishers' do
    it 'bootstraps' do
      Promiscuous.context { 10.times { PublisherModel.create } }

      switch_mode(:bootstrap => true)
      Promiscuous::Publisher::Bootstrap::Version.new.bootstrap
      Promiscuous::Publisher::Bootstrap::Data.new.bootstrap
      eventually { SubscriberModel.count.should == PublisherModel.count }

      switch_mode(:bootstrap => false)
      PublisherModel.all.each { |pub| Promiscuous.context { pub.update_attributes(:field_1 => 'ohai') } }
      eventually { SubscriberModel.each { |sub| sub.field_1.should == 'ohai' } }
    end
  end

  context 'when updates happens after the version bootstrap, but before the document is replicated', :pending => true do
    it 'bootstraps' do
      Promiscuous.context { 10.times { PublisherModel.create } }

      switch_mode(:bootstrap => true)
      Promiscuous::Publisher::Bootstrap::Version.new.bootstrap

      switch_mode(:bootstrap => false)
      @worker.stop; @worker = nil
      Promiscuous.context { PublisherModel.first.update_attributes(:field_2 => 'hello') }

      switch_mode(:bootstrap => true)
      Promiscuous::Publisher::Bootstrap::Data.new.bootstrap
      eventually { SubscriberModel.count.should == PublisherModel.count }

      SubscriberModel.first.field_2.should == nil

      switch_mode(:bootstrap => false)
      eventually { SubscriberModel.first.field_2.should == 'hello' }
      PublisherModel.all.each { |pub| Promiscuous.context { pub.update_attributes(:field_1 => 'ohai') } }
      eventually { SubscriberModel.each { |sub| sub.field_1.should == 'ohai' } }
    end
  end
end
