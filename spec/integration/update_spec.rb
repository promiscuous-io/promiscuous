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
        field :field_4
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

      field :field_4, :default => 'not_updated'
    end
  end

  context 'when replicating the update of a model' do
    before { Replicable::Subscriber::Worker.run }

    let!(:instance) { PublisherModel.create }

    it 'updates the model' do
      instance.update_attributes(:field_1 => 'updated')
      eventually { SubscriberModel.find(instance.id).field_1.should == 'updated' }
    end

    it 'does not update fields that are not subscribed to' do
      instance.update_attributes(:field_1 => 'updated', :field_4 => 'updated')
      eventually do
        sub = SubscriberModel.find(instance.id)
        sub.field_1.should == 'updated'
        sub.field_4.should == 'not_updated'
      end
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

    it 'updates the model' do
      instance.update_attributes(:field_1 => 'updated')
      eventually { SubscriberModelChild.find(instance.id).field_1.should == 'updated' }
    end
  end

  context "with polymorphic model with explicit replicating fields on a child" do
    before do
      define_constant(:publisher_model_child, PublisherModel) do
        include Mongoid::Document
        replicate do
          field :child_field, :default => 'publisher'
        end
      end
      define_constant(:subscriber_model_child, SubscriberModel) do
        include Mongoid::Document
        replicate :from => 'test_publisher', :class_name => 'publisher_model_child' do
          field :child_field, :default => 'subscriber'
        end
      end
    end

    before { Replicable::Subscriber::Worker.run }

    it 'updates the subscriber field' do
      instance = PublisherModelChild.create
      instance.update_attributes(:child_field => 'update')
      eventually { SubscriberModel.find(instance.id).child_field.should == 'update' }
    end
  end

  context "with polymorphic model with explicit replication excluding a field that is replicated" do
    before do
      define_constant(:publisher_model_child, PublisherModel) do
        include Mongoid::Document
        replicate do
          field :child_field_1, :default => 'publisher_1'
          field :child_field_2, :default => 'publisher_2'
        end
      end
      define_constant(:subscriber_model_child, SubscriberModel) do
        include Mongoid::Document
        replicate :from => 'test_publisher', :class_name => 'publisher_model_child' do
          field :child_field_1, :default => 'subscriber_1'
        end
        field :child_field_2, :default => 'subscriber_2'
      end
    end

    before { Replicable::Subscriber::Worker.run }

    it 'does not replicate the subscriber field' do
      instance = PublisherModelChild.create
      instance.update_attributes(:child_field_1 => 'update_1',
                                 :child_field_2 => 'update_2')

      eventually do
        m = SubscriberModel.find(instance.id)
        m.child_field_1.should == 'update_1'
        m.child_field_2.should == 'subscriber_2'
      end
    end
  end

  context "with implicit polymorphic model" do
    it 'replicates the models' do
      define_constant(:model_child, SubscriberModel)
      Replicable::Subscriber::Worker.run
      Object.send(:remove_const, 'ModelChild')

      define_constant(:model_child, PublisherModel)
      instance = ModelChild.create
      ModelChild.first.update_attributes(:field_1 => 'update')
      Object.send(:remove_const, 'ModelChild')

      define_constant(:model_child, SubscriberModel)
      eventually { ModelChild.find(instance.id).field_1.should == 'update' }
    end
  end


  context 'when replicating the update of a model that fails' do
    let!(:error_handler) { proc { |exception| @error_handler_called_with = exception } }

    before { use_real_amqp(:error_handler => error_handler, :logger_level => Logger::FATAL) }
    before { Replicable::Subscriber::Worker.run }
    before { SubscriberModel.class_eval { validates_format_of :field_1, :without => /updated/ } }

    let!(:instance) { PublisherModel.create }

    it 'calls the error_handler with an exception' do
      instance.update_attributes(:field_1 => 'updated')
      eventually { @error_handler_called_with.should be_a(Exception) }
    end

    it 'stops processing anything' do
      instance.update_attributes(:field_1 => 'updated')
      instance.update_attributes(:field_1 => 'another_update')

      eventually { @error_handler_called_with.should be_a(Exception) }
      EM::Synchrony.sleep 0.5
      eventually { SubscriberModel.find(instance.id).field_1.should_not == 'another_update' }
    end
  end

  after do
    Replicable::AMQP.close
    Replicable::Subscriber.subscriptions.clear
  end
end
