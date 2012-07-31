require 'spec_helper'
require 'replicable/subscriber/worker'

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

      replicate :from => 'crowdtap', :class_name => 'publisher_model' do
        field :field_1
        field :field_2
        field :field_3
      end
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
      eventually { SubscriberModel.where(:_id => id).count.should == 1}
    end

    it 'persists fields that its subscribed to' do
      id = PublisherModel.create!(:field_1 => '1').id
      eventually { SubscriberModel.where(:_id => id).first.field_1.should == '1' }
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

        replicate :from => 'crowdtap', :class_name => 'publisher_model2' do
          field :field_1
          field :field_2
          field :field_3
        end
      end
    end

    before { Replicable::Subscriber::Worker.run }

    it 'replicates the models' do
      id = PublisherModel.create.id
      id2 = PublisherModel2.create.id
      eventually { SubscriberModel.where(:_id => id).count.should == 1}
      eventually { SubscriberModel2.where(:_id => id2).count.should == 1}
    end
  end

  after do
    Replicable::AMQP.close
    Replicable::Subscriber.subscriptions.clear
  end
end
