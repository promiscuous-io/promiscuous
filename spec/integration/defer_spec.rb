require 'spec_helper'

if ORM.has(:pub_deferred_updates)
  describe Promiscuous do
    before { load_models }
    before { use_real_amqp }

    before do
      define_constant('Publisher', ORM::PublisherBase) do
        publish :to => 'crowdtap/publisher_model',
          :class => :PublisherModel,
          :attributes => [:field_1, :field_2, :field_3]
      end

      define_constant('Subscriber', ORM::SubscriberBase) do
        subscribe :from => 'crowdtap/publisher_model',
          :class => :SubscriberModel,
          :attributes => [:field_1, :field_2, :field_3]
      end
    end

    before { Promiscuous::Worker.replicate }

    context 'when publishing' do
      context 'when updating' do
        it 'replicates' do
          2.times do
            3.times do
              pub = PublisherModel.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')
              pub.update_attributes(:field_1 => '1_updated', :field_2 => '2_updated')
            end

            eventually do
              PublisherModel.each do |pub|
                sub = SubscriberModel.find(pub.id)
                sub.field_1.should == pub.field_1
                sub.field_2.should == pub.field_2
                sub.field_3.should == pub.field_3
              end
            end
          end
        end

        it 'eventually leaves the published model intact' do
          pub = PublisherModel.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')
          pub.update_attributes(:field_1 => '1_updated', :field_2 => '2_updated')
          eventually do
            sub = SubscriberModel.first
            sub.field_1.should == pub.field_1
            pub.reload
            pub.promiscous_sync_pending.should == nil
          end
        end

        it 'replicates increments properly, even with high concurrency' do
          pub = PublisherModel.create(:field_1 => 0)
          100.times { EM.defer { pub.inc(:field_1, 1) } }
          eventually { SubscriberModel.first.field_1.should == 100 }
        end
      end
    end

    context 'when not publishing some models' do
      it 'does not set the promiscous_sync_pending' do
        PublisherModel.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')
        eventually do
          SubscriberModel.first.should_not == nil
        end

        pub = PublisherModelOther.create(:field_1 => '1', :field_2 => '2', :field_3 => '3')
        pub.update_attributes(:field_1 => '1_updated', :field_2 => '2_updated')
        pub.reload
        pub.attributes.keys.should =~ ["_id", "field_1", "field_2", "field_3"]
      end
    end
  end
end
