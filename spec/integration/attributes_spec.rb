require 'spec_helper'

describe Promiscuous do
  before { use_real_backend }
  before { load_models }
  before { run_subscriber_worker! }

  context 'using virtual attributes' do
    before do
      class PublisherModel
        publish :vattr, :use => :field_1

        def vattr
          "#{field_1}!"
        end
      end

      class SubscriberModel
        cattr_accessor :vattr_value
        subscribe :vattr

        def vattr=(value)
          self.class.vattr_value = value
        end
      end
    end

    it 'replicates' do
      pub = nil
      Promiscuous.context do
        pub = PublisherModel.create(:field_1 => '1')
        pub.update_attributes(:field_1 => 'super')
      end

      eventually do
        SubscriberModel.vattr_value.should == 'super!'
      end
    end
  end
end
