require 'spec_helper'
require 'replicable/subscriber/worker'

describe Replicable do
  before { use_real_amqp }

  before do
    define_constant(:publisher_model) do
      include Mongoid::Document
      include Replicable::Publisher

      replicate :app_name => 'test_publisher' do
        field :field_1
        field :field_2
        field :field_3
      end
    end

    define_constant(:subscriber_model) do
      include Mongoid::Document
      include Replicable::Subscriber

      replicate :from => 'test_publisher', :class_name => 'publisher_model' do
        field :field_1
        field :field_2
        field :field_3
      end
    end
  end


  context 'when replicating the destruction of a model' do
    before { Replicable::Subscriber::Worker.run }

    let!(:instance) { PublisherModel.create }

    it 'destroys the model' do
      eventually { SubscriberModel.where(:_id => instance.id).count.should == 1 }
      instance.destroy
      eventually { SubscriberModel.where(:_id => instance.id).count.should == 0 }
    end
  end

  context "with polymorphic models" do
    before do
      define_constant(:publisher_model_child, PublisherModel) do
        include Mongoid::Document
      end
      define_constant(:subscriber_model_child, SubscriberModel) do
        include Mongoid::Document
        replicate :from => 'test_publisher', :class_name => 'publisher_model_child'
      end
    end

    before { Replicable::Subscriber::Worker.run }

    let!(:instance) { PublisherModelChild.create }

    it 'destroys the model' do
      eventually { SubscriberModelChild.where(:_id => instance.id).count.should == 1 }
      instance.destroy
      eventually { SubscriberModelChild.where(:_id => instance.id).count.should == 0 }
    end
  end

  after do
    Replicable::AMQP.close
    Replicable::Subscriber.subscriptions.clear
  end
end
