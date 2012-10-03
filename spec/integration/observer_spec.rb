require 'spec_helper'
require 'promiscuous/worker'

describe Promiscuous do
  before { load_models; load_observers }
  before { use_real_amqp }

  before do
    define_constant(:Publisher, ORM::PublisherBase) do
      publish :to => 'crowdtap/publisher_model',
              :class => :PublisherModel,
              :attributes => [:field_1, :field_2, :field_3]
    end

    define_constant(:Subscriber, Promiscuous::Subscriber::Observer) do
      subscribe :from => 'crowdtap/publisher_model',
                :class => :ModelObserver,
                :attributes => [:field_1, :field_2, :field_3]
    end

    ModelObserver.class_eval do
      [:create, :update, :destroy].each do |cb|
        called_with = "#{cb}_instance"
        cattr_accessor "#{cb}_instance"
        __send__("after_#{cb}", proc { self.class.send("#{called_with}=", self) })
      end
    end
  end

  before { Promiscuous::Worker.replicate }

  context 'when creating' do
    it 'triggers the create callbacks' do
      pub = PublisherModel.new(:field_1 => '1', :field_2 => '2', :field_3 => '3')
      pub.save

      eventually do
        obs = ModelObserver.create_instance
        # XXX Note that the observer's id is a string (due to JSON serialization)
        obs.id.should == pub.id.to_s
        obs.field_1.should == pub.field_1
        obs.field_2.should == pub.field_2
        obs.field_3.should == pub.field_3
      end
    end
  end

  context 'when updating' do
    it 'triggers the update callbacks' do
      pub = PublisherModel.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')
      pub.update_attributes(:field_1 => '1_updated', :field_2 => '2_updated')

      eventually do
        obs = ModelObserver.update_instance
        obs.id.should == pub.id.to_s
        obs.field_1.should == pub.field_1
        obs.field_2.should == pub.field_2
        obs.field_3.should == pub.field_3
      end
    end
  end

  context 'when destroying' do
    it 'triggers the destroy callbacks' do
      pub = PublisherModel.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')

      pub.destroy
      eventually { ModelObserver.destroy_instance.id.should == pub.id.to_s }
    end
  end

  after do
    Promiscuous::AMQP.disconnect
    Promiscuous::Subscriber::AMQP.subscribers.clear
  end
end
