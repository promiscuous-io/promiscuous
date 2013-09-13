require 'spec_helper'

describe Promiscuous do
  before { load_models }
  before do
    define_constant :InvalidSchemaSubscriberModel do
      include Mongoid::Document
      include Promiscuous::Subscriber

      subscribe :from => 'publisher_model' do
        field :field_1
        field :fieldX
      end
    end
  end
  before { use_real_backend { |config| config.logger.level = Logger::FATAL } }
  before { run_subscriber_worker! }

  context 'without relaxed schema checking' do
    before { Promiscuous::Config.relaxed_schema = false }

    it "doesn't replicate" do
      pub = Promiscuous.context do
        pub = PublisherModel.new(:field_1 => '1')
        pub.save
        pub
      end
      pub.reload

      sleep 1

      InvalidSchemaSubscriberModel.first.should be_nil
    end
  end

  context 'with relaxed schema checking' do
    before { Promiscuous::Config.relaxed_schema = true }

    it "replicates" do
      pub = Promiscuous.context do
        pub = PublisherModel.new(:field_1 => '1')
        pub.save
        pub
      end
      pub.reload

      eventually do
        sub = InvalidSchemaSubscriberModel.first
        sub.id.should == pub.id
        sub.field_1.should == pub.field_1
      end
    end
  end
end
