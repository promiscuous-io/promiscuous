require 'spec_helper'

describe Promiscuous, 'bootstrapping' do
  before { use_real_backend }
  before { Promiscuous::Config.hash_size = 100 }
  before { load_models }


  describe 'versions' do
    it 'publishes' do
      num_models = 100
      Promiscuous.context do
        num_models.times { PublisherModel.create }
      end

      Promiscuous::Config.bootstrap = true
      run_subscriber_bootstrap_worker!

      Promiscuous::Publisher::Bootstrap.new.bootstrap

      eventually { SubscriberModel.count.should == num_models }
      Promiscuous::Config.bootstrap = false
      run_subscriber_worker!

      use_null_backend
      use_real_backend

      Promiscuous.context do
        PublisherModel.all.without_promiscuous.each { |pub| pub.update_attributes(:field_1 => 'ohai') }
      end

      eventually do
        SubscriberModel.each { |sub| sub.field_1.should == 'ohai' }
      end
    end
  end
end
