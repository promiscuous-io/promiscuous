require 'spec_helper'
require 'replicable/subscriber/worker'

# TODO autodestroy queues, etc.
# API block

describe Replicable do
  before do
    define_constant(:publisher_model) do
      include Mongoid::Document
      include Replicable::Publisher

      field :field_1
      field :field_2
      field :field_3

      replicate :app_name => 'crowdtap'
    end

    define_constant(:subscriber_model) do
      include Mongoid::Document
      include Replicable::Subscriber

      field :field_1
      field :field_2
      field :field_3

      replicate :from => 'crowdtap',
                :class_name => 'publisher_model',
                :fields => [:field_1, :field_2, :field_3]
    end
  end

  before do
    Replicable::AMQP.configure(:backend => :rubyamqp, :app => 'sniper',
                               :queue_options => {:auto_delete => true})
  end

  context 'when replicating the creation of a model' do
    before { Replicable::Subscriber::Worker.run }

    it 'creates the model' do
      PublisherModel.create
      eventually { SubscriberModel.all.count.should == 1 }
    end

    it 'persists the model with the same id' do
      id = PublisherModel.create.id
      eventually { SubscriberModel.where(:id => id).count.should == 1}
    end

    it 'persists fields that its subscribed to' do
      id = PublisherModel.create!(:field_1 => '1').id
      eventually { SubscriberModel.where(:id => id).first.field_1.should == '1' }
    end
  end

  context "with multiple models" do
    before do
      define_constant(:publisher_model2) do
        include Mongoid::Document
        include Replicable::Publisher

        field :field_1
        field :field_2
        field :field_3

        replicate :app_name => 'crowdtap'
      end

      define_constant(:subscriber_model2) do
        include Mongoid::Document
        include Replicable::Subscriber

        field :field_1
        field :field_2
        field :field_3

        replicate :from => 'crowdtap',
                  :class_name => 'publisher_model2',
                  :fields => [:field_1, :field_2, :field_3]
      end
    end

    before { Replicable::Subscriber::Worker.run }

    it 'replicates the models' do
      id = PublisherModel.create.id
      id2 = PublisherModel2.create.id
      eventually { SubscriberModel.where(:id => id).count.should == 1}
      eventually { SubscriberModel2.where(:id => id2).count.should == 1}
    end
  end

  after do
    Replicable::AMQP.close
    Replicable::Subscriber.subscriptions.clear
  end
end
