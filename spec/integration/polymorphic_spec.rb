require 'spec_helper'

if ORM.has(:polymorphic)
  describe Promiscuous do
    before { load_models }
    before { use_real_backend }

    context 'when not collapsing the polymorhic hierarchy' do
      before { run_subscriber_worker! }

      context 'when creating' do
        it 'replicates the parent' do
          pub = PublisherModel.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')

          eventually do
            sub = SubscriberModel.find(pub.id)
            sub.id.should == pub.id
            sub.field_1.should == pub.field_1
            sub.field_2.should == pub.field_2
            sub.field_3.should == pub.field_3
          end
        end

        it 'replicates the child' do
          pub = PublisherModelChild.create(:field_1 => '1', :field_2 => '2', :field_3 => '3',
                                           :child_field_1 => 'child_1')

          eventually do
            sub = SubscriberModelChild.find(pub.id)
            sub.id.should == pub.id
            sub.field_1.should == pub.field_1
            sub.field_2.should == pub.field_2
            sub.field_3.should == pub.field_3
            sub.child_field_1.should == pub.child_field_1
          end
        end

      end

      context 'when updating' do
        it 'replicates the parent' do
          pub = PublisherModel.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')
          pub.update_attributes(:field_1 => '1_updated', :field_2 => '2_updated')

          eventually do
            sub = SubscriberModel.find(pub.id)
            sub.id.should == pub.id
            sub.field_1.should == pub.field_1
            sub.field_2.should == pub.field_2
            sub.field_3.should == pub.field_3
          end
        end

        it 'replicates the child' do
          pub = PublisherModelChild.create(:field_1 => '1', :field_2 => '2', :field_3 => '3',
                                           :child_field_1 => 'child_1')
          pub.update_attributes(:field_1 => '1_updated', :field_2 => '2_updated',
                                :child_field_1 => 'child_1_updated')

          eventually do
            sub = SubscriberModelChild.find(pub.id)
            sub.id.should == pub.id
            sub.field_1.should == pub.field_1
            sub.field_2.should == pub.field_2
            sub.field_3.should == pub.field_3
            sub.child_field_1.should == pub.child_field_1
          end
        end
      end

      context 'when destroying' do
        it 'replicates the parent' do
          pub = PublisherModel.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')

          eventually { SubscriberModel.count.should == 1 }
          pub.destroy
          eventually { SubscriberModel.count.should == 0 }
        end

        it 'replicates the child' do
          pub = PublisherModelChild.create(:field_1 => '1', :field_2 => '2', :field_3 => '3',
                                           :child_field_1 => 'child_1')

          eventually { SubscriberModelChild.count.should == 1 }
          pub.destroy
          eventually { SubscriberModelChild.count.should == 0 }
        end
      end
    end

    context 'when collapsing a polymorphic hierarchy' do
      before do
        define_constant :Publisher1 do
          include Mongoid::Document
          include Promiscuous::Publisher
          field :field_1
          publish :field_1, :to => 'crowdtap/publisher'
        end

        define_constant :Publisher2, Publisher1 do
          field :field_2
          publish :field_2
        end

        define_constant :Publisher3, Publisher2 do
          field :field_3
          publish :field_3
        end

        define_constant :Subscriber1 do
          include Mongoid::Document
          include Promiscuous::Subscriber
          field :field_1
          subscribe :as => :Publisher1, :from => 'crowdtap/publisher'
          subscribe :field_1
        end

        define_constant :Subscriber2, Subscriber1 do
          field :field_2
          subscribe :as => :Publisher2
          subscribe :field_2
        end
      end

      before { run_subscriber_worker! }

      it 'replicates' do
        pub1 = Publisher1.create(:field_1 => '11')
        pub2 = Publisher2.create(:field_1 => '21', :field_2 => '22')
        pub3 = Publisher3.create(:field_1 => '31', :field_2 => '32', :field_3 => '33')

        eventually do
          Subscriber1.find(pub1.id).tap do |sub1|
            sub1.field_1.should == '11'
          end
          Subscriber2.find(pub2.id).tap do |sub2|
            sub2.field_1.should == '21'
            sub2.field_2.should == '22'
          end
          Subscriber2.find(pub3.id).tap do |sub3|
            sub3.field_1.should == '31'
            sub3.field_2.should == '32'
          end
        end
      end
    end

    context 'when subscirbing to child classes individually' do
      before do
        define_constant :PublisherModelHidden do
          include Mongoid::Document
          field :field_1
        end

        define_constant :PublisherModelChildRoot, PublisherModelHidden do
          include Promiscuous::Publisher
          field :child_field_1
          publish :field_1, :child_field_1, :to => 'crowdtap/publisher_child_model'
        end

        define_constant :PublisherModelAnotherChildRoot, PublisherModelHidden do
          include Promiscuous::Publisher
          field :another_child_field_1
          publish :field_1, :another_child_field_1, :to => 'crowdtap/publisher_another_child_model'
        end

        define_constant :SubscriberModelHidden do
          include Mongoid::Document
          field :field_1
        end

        define_constant :SubscriberModelChildRoot, SubscriberModelHidden do
          include Promiscuous::Subscriber
          field :child_field_1
          subscribe :from => 'crowdtap/publisher_child_model'
          subscribe :as   =>  :PublisherModelChildRoot
          subscribe :field_1, :child_field_1
        end

        define_constant :SubscriberModelAnotherChildRoot, SubscriberModelHidden do
          include Promiscuous::Subscriber
          field :another_child_field_1
          subscribe :from => 'crowdtap/publisher_another_child_model'
          subscribe :as   =>  :PublisherModelAnotherChildRoot
          subscribe :field_1, :another_child_field_1
        end
      end

      before { run_subscriber_worker! }

      context 'when creating' do
        it 'replicates both child models' do
          pub1 = PublisherModelChildRoot.create(:field_1 => '1', :child_field_1 => '2')
          pub2 = PublisherModelAnotherChildRoot.create(:field_1 => '1', :another_child_field_1 => '2')

          eventually do
            sub1 = SubscriberModelChildRoot.find(pub1.id)
            sub1.id.should == pub1.id
            sub1.field_1.should == pub1.field_1
            sub1.child_field_1.should == pub1.child_field_1

            sub2 = SubscriberModelAnotherChildRoot.find(pub2.id)
            sub2.id.should == pub2.id
            sub2.field_1.should == pub2.field_1
            sub2.another_child_field_1.should == pub2.another_child_field_1
          end
        end
      end

      context 'when updating' do
        it 'replicates both child models' do
          pub1 = PublisherModelChildRoot.create(:field_1 => '1', :child_field_1 => '2')
          pub2 = PublisherModelAnotherChildRoot.create(:field_1 => '1', :another_child_field_1 => '2')

          pub1.update_attributes(:field_1 => '1_updated', :child_field_1 => '2_updated')
          pub2.update_attributes(:field_1 => '1_updated', :another_child_field_1 => '2_updated')

          eventually do
            sub1 = SubscriberModelChildRoot.find(pub1.id)
            sub1.id.should == pub1.id
            sub1.field_1.should == pub1.field_1
            sub1.child_field_1.should == pub1.child_field_1

            sub2 = SubscriberModelAnotherChildRoot.find(pub2.id)
            sub2.id.should == pub2.id
            sub2.field_1.should == pub2.field_1
            sub2.another_child_field_1.should == pub2.another_child_field_1
          end
        end
      end

      context 'when destroying' do
        it 'replicates the parent' do
          pub1 = PublisherModelChildRoot.create(:field_1 => '1', :child_field_1 => '2')
          pub2 = PublisherModelAnotherChildRoot.create(:field_1 => '1', :another_child_field_1 => '2')

          eventually do
            SubscriberModelChildRoot.count.should == 1
            SubscriberModelAnotherChildRoot.count.should == 1
          end
          pub1.destroy
          pub2.destroy
          eventually do
            SubscriberModelChildRoot.count.should == 0
            SubscriberModelAnotherChildRoot.count.should == 0
          end
        end
      end
    end
  end
end
