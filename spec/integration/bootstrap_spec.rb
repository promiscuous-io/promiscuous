require 'spec_helper'

describe Promiscuous, 'bootstrapping dependencies' do
  before { use_fake_backend }
  before { load_models }
  before { run_subscriber_worker! }

  #
  # TODO Test that the bootstrap exchange is used for both Data and Version
  #

  context 'when in publisher is in bootstrapping mode' do
    before { Promiscuous::Publisher::Bootstrap::Mode.enable }

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

      dep['read'].should == nil
      dep['write'].should == hashed["publisher_models/id/#{pub2.id}:1", "publisher_models/id/#{pub1.id}:2"]
    end
  end

  context 'when publisher is not in bootstrapping mode' do
    before { Promiscuous::Publisher::Bootstrap::Mode.disable }

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
      Promiscuous::Publisher::Bootstrap::Mode.enable
      Promiscuous.context { 10.times { PublisherModel.create } }

      switch_subscriber_mode(:pass1)
      Promiscuous::Publisher::Bootstrap::Version.bootstrap
      sleep 1
      Promiscuous::Publisher::Bootstrap::Mode.disable

      switch_subscriber_mode(:pass2)
      Promiscuous::Publisher::Bootstrap::Data.setup
      Promiscuous::Publisher::Bootstrap::Data.start

      eventually { SubscriberModel.count.should == PublisherModel.count }

      switch_subscriber_mode(false)
      PublisherModel.all.each { |pub| Promiscuous.context { pub.update_attributes(:field_1 => 'ohai') } }
      eventually { SubscriberModel.each { |sub| sub.field_1.should == 'ohai' } }
    end
  end

  context 'when updates happens after the version bootstrap, but before the document is replicated' do
    it 'bootstraps' do
      Promiscuous::Publisher::Bootstrap::Mode.enable
      Promiscuous.context { 10.times { PublisherModel.create } }

      switch_subscriber_mode(:pass1)

      Promiscuous::Publisher::Bootstrap::Version.bootstrap
      sleep 1
      Promiscuous::Publisher::Bootstrap::Mode.disable

      Promiscuous.context { PublisherModel.first.update_attributes(:field_2 => 'hello') }

      switch_subscriber_mode(:pass2)
      Promiscuous::Publisher::Bootstrap::Data.setup
      Promiscuous::Publisher::Bootstrap::Data.start
      eventually { SubscriberModel.count.should == PublisherModel.count - 1 }

      SubscriberModel.first.field_2.should == nil

      # TODO implement bootstrap pass3
      # switch_subscriber_mode(:pass3)
      # eventually { SubscriberModel.first.field_2.should == 'hello' }

      switch_subscriber_mode(false)
      eventually { SubscriberModel.first.field_2.should == 'hello' }
      PublisherModel.all.each { |pub| Promiscuous.context { pub.update_attributes(:field_1 => 'ohai') } }
      eventually { SubscriberModel.each { |sub| sub.field_1.should == 'ohai' } }
    end
  end

  context 'when bootstrapping an observer' do
    before { load_observers }
    before do
      ModelObserver.class_eval do
        cattr_accessor :saved, :created

        after_save   { self.saved = true }
        after_create { self.created = true }
      end
    end

    it 'calls the create and save observers' do
      Promiscuous::Publisher::Bootstrap::Mode.enable
      Promiscuous.context { PublisherModel.create }

      switch_subscriber_mode(:pass1)
      Promiscuous::Publisher::Bootstrap::Version.bootstrap
      switch_subscriber_mode(:pass2)
      Promiscuous::Publisher::Bootstrap::Data.setup
      Promiscuous::Publisher::Bootstrap::Data.start

      eventually do
        ModelObserver.saved.should == true
        ModelObserver.created.should == true
      end
    end
  end

  describe 'bootstrapping large number of docs split over ranges of multiple models' do
    let(:number_of_docs) { 51 }
    let(:range_size)     { 9 }
    before do
      $counter = 0
      SubscriberModel.class_eval do
        after_save { $counter += 1 }
      end
      $other_counter = 0
      SubscriberModelOther.class_eval do
        after_save { $other_counter += 1 }
      end
    end
    before { Promiscuous::Publisher::Bootstrap::Mode.enable }
    before { Promiscuous.context { number_of_docs.times { |i| model = PublisherModel.new; model.id = Moped::BSON::ObjectId.from_time(Time.now + i.seconds); model.save } } }
    before { Promiscuous.context { number_of_docs.times { |i| model = PublisherModelOther.new; model.id = Moped::BSON::ObjectId.from_time(Time.now + i.seconds); model.save } } }

    it "bootstraps" do
      switch_subscriber_mode(:pass1)
      Promiscuous::Publisher::Bootstrap::Version.bootstrap
      sleep 1
      Promiscuous::Publisher::Bootstrap::Mode.disable

      switch_subscriber_mode(:pass2)
      Promiscuous::Publisher::Bootstrap::Data.setup(:range_size => range_size)
      Promiscuous::Publisher::Bootstrap::Data.start(:lock => { :expire => 2.seconds }) # Ensure that we extend the lock

      eventually do
        SubscriberModel.count.should == PublisherModel.count
        SubscriberModelOther.count.should == PublisherModelOther.count
        $counter.should == SubscriberModel.count
        $other_counter.should == SubscriberModelOther.count
      end
    end
  end
end

def switch_subscriber_mode(bootstrap_mode)
  Promiscuous::Config.configure { |config| config.bootstrap = bootstrap_mode }
  if @worker
    @worker.pump.recover # send the nacked message again
  else
    run_subscriber_worker!
  end
end
