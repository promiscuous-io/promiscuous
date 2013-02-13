require 'spec_helper'

describe Promiscuous do
  before { load_models }
  before { use_real_backend }
  before { run_subscriber_worker! }

  context "single attributes definition" do
    before do
      Promiscuous.define do
        publish :publisher_dsl_models, :to => 'crowdtap/publisher_model' do
          attributes :field_1, :field_2
        end
      end

      Promiscuous.define do
        subscribe :subscriber_dsl_models, :from => 'crowdtap/publisher_model' do
          attributes :field_1, :field_2
        end
      end
    end

    it 'replicates' do
      pub = PublisherDslModel.new(:field_1 => '1', :field_2 => '2')
      pub.save

      eventually do
        sub = SubscriberDslModel.first
        sub.id.should == pub.id
        sub.field_1.should == pub.field_1
        sub.field_2.should == pub.field_2
      end
    end
  end

  context "multiple attributes definitions" do
    before do
      Promiscuous.define do
        publish :publisher_dsl_models, :to => 'crowdtap/publisher_model' do
          attributes :field_1
          attributes :field_2
        end
      end

      Promiscuous.define do
        subscribe :subscriber_dsl_models, :from => 'crowdtap/publisher_model' do
          attributes :field_1
          attributes :field_2
        end
      end
    end

    it 'replicates' do
      pub = PublisherDslModel.new(:field_1 => '1', :field_2 => '2', :field_3 => '3')
      pub.save

      eventually do
        sub = SubscriberDslModel.first
        sub.id.should == pub.id
        sub.field_1.should == pub.field_1
        sub.field_2.should == pub.field_2
      end
    end
  end
end
