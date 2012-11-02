require 'spec_helper'

if ORM.has(:polymorphic)
  describe Promiscuous do
    before { load_models }
    before { use_real_amqp }

    context 'when not collapsing the polymorhic hierarchy' do
      before do
        define_constant('Publisher', ORM::PublisherBase) do
          publish :to => 'crowdtap/publisher_model',
                  :class => :PublisherModel,
                  :attributes => [:field_1, :field_2, :field_3]
        end

        define_constant('PublisherChild', Publisher) do
          publish :class => :PublisherModelChild,
                  :attributes => [:child_field_1]
        end

        define_constant('Subscriber', ORM::SubscriberBase) do
          subscribe :from => 'crowdtap/publisher_model',
                    :from_type => :PublisherModel,
                    :class => :SubscriberModel,
                    :attributes => [:field_1, :field_2, :field_3]
        end

        define_constant('SubscriberChild', Subscriber) do
          subscribe :from_type => :PublisherModelChild,
                    :class => :SubscriberModelChild,
                    :attributes => [:child_field_1]
        end
      end

      before { Promiscuous::Worker.replicate }

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
        define_constant('Publisher', ORM::PublisherBase) do
          publish :to => 'crowdtap/publisher_model',
                  :class => :PublisherModel,
                  :attributes => [:field_1, :field_2, :field_3]
        end

        define_constant('PublisherChild', Publisher) do
          publish :class => :PublisherModelChild,
                  :attributes => [:child_field_1]
        end

        define_constant('Subscriber', ORM::SubscriberBase) do
          subscribe :from => 'crowdtap/publisher_model',
                    :from_type => :PublisherModel,
                    :class => :SubscriberModelChild,
                    :attributes => [:field_1, :field_2, :field_3]
        end

        define_constant('SubscriberChild', Subscriber) do
          subscribe :from_type => :PublisherModelChild,
                    :attributes => [:child_field_1]
        end
      end

      before { Promiscuous::Worker.replicate }

      it 'doesn\'t replicate child fields' do
        SubscriberModelChild.class_eval { field :child_field_1, :default => "default" }
        pub = PublisherModel.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')

        eventually do
          sub = SubscriberModelChild.find(pub.id)
          sub.child_field_1.should == 'default'
        end
      end
    end

    context 'when subscirbing to child classes individually' do
      before do
        define_constant('PublisherChild', ORM::PublisherBase) do
          publish :to => 'crowdtap/publisher_child_model',
                  :class => :PublisherModelChild,
                  :attributes => [:field_1, :child_field_1]
        end

        define_constant('PublisherAnotherChild', ORM::PublisherBase) do
          publish :to => 'crowdtap/publisher_another_child_model',
                  :class => :PublisherModelAnotherChild,
                  :attributes => [:field_1, :another_child_field_1]
        end

        define_constant('SubscriberChild', ORM::SubscriberBase) do
          subscribe :from => 'crowdtap/publisher_child_model',
                    :from_type => :PublisherModelChild,
                    :class => :SubscriberModelChild,
                    :attributes => [:field_1, :child_field_1]
        end

        define_constant('SubscriberAnotherChild', ORM::SubscriberBase) do
          subscribe :from => 'crowdtap/publisher_another_child_model',
                    :from_type => :PublisherModelAnotherChild,
                    :class => :SubscriberModelAnotherChild,
                    :attributes => [:field_1, :another_child_field_1]
        end
      end

      before { Promiscuous::Worker.replicate }

      context 'when creating' do
        it 'replicates both child models' do
          pub1 = PublisherModelChild.create(:field_1 => '1', :child_field_1 => '2')
          pub2 = PublisherModelAnotherChild.create(:field_1 => '1', :another_child_field_1 => '2')

          eventually do
            sub1 = SubscriberModelChild.find(pub1.id)
            sub1.id.should == pub1.id
            sub1.field_1.should == pub1.field_1
            sub1.child_field_1.should == pub1.child_field_1

            sub2 = SubscriberModelAnotherChild.find(pub2.id)
            sub2.id.should == pub2.id
            sub2.field_1.should == pub2.field_1
            sub2.another_child_field_1.should == pub2.another_child_field_1
          end
        end
      end

      context 'when updating' do
        it 'replicates both child models' do
          pub1 = PublisherModelChild.create(:field_1 => '1', :child_field_1 => '2')
          pub2 = PublisherModelAnotherChild.create(:field_1 => '1', :another_child_field_1 => '2')

          pub1.update_attributes(:field_1 => '1_updated', :child_field_1 => '2_updated')
          pub2.update_attributes(:field_1 => '1_updated', :another_child_field_1 => '2_updated')

          eventually do
            sub1 = SubscriberModelChild.find(pub1.id)
            sub1.id.should == pub1.id
            sub1.field_1.should == pub1.field_1
            sub1.child_field_1.should == pub1.child_field_1

            sub2 = SubscriberModelAnotherChild.find(pub2.id)
            sub2.id.should == pub2.id
            sub2.field_1.should == pub2.field_1
            sub2.another_child_field_1.should == pub2.another_child_field_1
          end
        end
      end

      context 'when destroying' do
        it 'replicates the parent' do
          pub1 = PublisherModelChild.create(:field_1 => '1', :child_field_1 => '2')
          pub2 = PublisherModelAnotherChild.create(:field_1 => '1', :another_child_field_1 => '2')

          eventually do
            SubscriberModelChild.count.should == 1
            SubscriberModelAnotherChild.count.should == 1
          end
          pub1.destroy
          pub2.destroy
          eventually do
            SubscriberModelChild.count.should == 0
            SubscriberModelAnotherChild.count.should == 0
          end
        end
      end
    end
  end
end
