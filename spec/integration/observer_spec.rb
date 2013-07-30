require 'spec_helper'

describe Promiscuous do
  before { load_models; load_observers }
  before { use_real_backend }

  before { run_subscriber_worker! }

  context 'when creating' do
    it 'triggers the create callbacks' do
      define_callback(:create)
      pub = nil
      Promiscuous.context do
        pub = PublisherModel.new(:field_1 => '1', :field_2 => '2', :field_3 => '3')
        pub.save
      end

      eventually do
        obs = ModelObserver.create_instance
        # XXX Note that the observer's id is a string (due to JSON serialization)
        obs.id.to_s.should == pub.id.to_s
        obs.field_1.should == pub.field_1
        obs.field_2.should == pub.field_2
        obs.field_3.should == pub.field_3
      end
    end

    it 'triggers the save callbacks' do
      define_callback(:save)
      pub = nil
      Promiscuous.context do
        pub = PublisherModel.new(:field_1 => '1', :field_2 => '2', :field_3 => '3')
        pub.save
      end

      eventually do
        obs = ModelObserver.save_instance
        # XXX Note that the observer's id is a string (due to JSON serialization)
        obs.id.to_s.should == pub.id.to_s
        obs.field_1.should == pub.field_1
        obs.field_2.should == pub.field_2
        obs.field_3.should == pub.field_3
      end
    end
  end

  context 'when updating' do
    it 'triggers the update callbacks' do
      define_callback(:update)
      pub = nil
      Promiscuous.context do
        pub = PublisherModel.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')
        pub.update_attributes(:field_1 => '1_updated', :field_2 => '2_updated')
      end

      eventually do
        obs = ModelObserver.update_instance
        obs.id.to_s.should == pub.id.to_s
        obs.field_1.should == pub.field_1
        obs.field_2.should == pub.field_2
        obs.field_3.should == pub.field_3
      end
    end

    it 'triggers the save callbacks' do
      define_callback(:save)
      pub = nil
      Promiscuous.context do
        pub = PublisherModel.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')
        pub.update_attributes(:field_1 => '1_updated', :field_2 => '2_updated')
      end

      eventually do
        obs = ModelObserver.save_instance
        obs.id.to_s.should == pub.id.to_s
        obs.field_1.should == pub.field_1
        obs.field_2.should == pub.field_2
        obs.field_3.should == pub.field_3
      end
    end
  end

  context 'when destroying' do
    it 'triggers the destroy callbacks' do
      define_callback(:destroy)
      pub = nil
      Promiscuous.context do
        pub = PublisherModel.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')
        pub.destroy
      end

      eventually { ModelObserver.destroy_instance.id.to_s.should == pub.id.to_s }
    end
  end
end

def define_callback(cb)
  ModelObserver.class_eval do
    cattr_accessor "#{cb}_instance"
    __send__("after_#{cb}", proc { self.class.send("#{cb}_instance=", self) })
  end
end
