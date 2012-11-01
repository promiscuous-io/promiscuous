require 'spec_helper'

if ORM.has(:many_embedded_documents)
  describe Promiscuous do
    before { load_models }
    before { use_real_amqp }

    before do
      define_constant('PublisherEmbedMany', ORM::PublisherBase) do
        publish :to => 'crowdtap/publisher_model_embed_many',
          :class => :PublisherModelEmbedMany,
          :attributes => [:field_1, :field_2, :field_3, :models_embedded]
      end

      define_constant('PublisherEmbedded', ORM::PublisherBase) do
        publish :to => 'crowdtap/model_embedded',
          :class => :PublisherModelEmbedded,
          :attributes => [:embedded_field_1, :embedded_field_2, :embedded_field_3]
      end

      define_constant('SubscriberEmbedMany', ORM::SubscriberBase) do
        subscribe :from => 'crowdtap/publisher_model_embed_many',
          :class => SubscriberModelEmbedMany,
          :attributes => [:field_1, :field_2, :field_3, :models_embedded]
      end

      define_constant('SubscriberEmbedded', ORM::SubscriberBase) do
        subscribe :from => 'crowdtap/model_embedded',
          :class => SubscriberModelEmbedded,
          :attributes => [:embedded_field_1, :embedded_field_2, :embedded_field_3]
      end
    end

    before { Promiscuous::Worker.replicate }

    context 'when creating' do
      context 'when the parent does not exist yet' do
        it 'replicates' do
          pub = PublisherModelEmbedMany.create(:field_1 => '1',
                                               :models_embedded => [{ :embedded_field_1 => 'e1',
                                                                      :embedded_field_2 => 'e2' },
                                                                    { :embedded_field_1 => 'e3',
                                                                      :embedded_field_2 => 'e4' }])
          pub_e1 = pub.models_embedded[0]
          pub_e2 = pub.models_embedded[1]

          eventually do
            sub = SubscriberModelEmbedMany.first
            sub_e1 = sub.models_embedded[0]
            sub_e2 = sub.models_embedded[1]
            sub.id.should == pub.id
            sub.field_1.should == pub.field_1
            sub.field_2.should == pub.field_2
            sub.field_3.should == pub.field_3

            sub_e1.id.should == pub_e1.id
            sub_e1.embedded_field_1.should == pub_e1.embedded_field_1
            sub_e1.embedded_field_2.should == pub_e1.embedded_field_2
            sub_e1.embedded_field_3.should == pub_e1.embedded_field_3

            sub_e2.id.should == pub_e2.id
            sub_e2.embedded_field_1.should == pub_e2.embedded_field_1
            sub_e2.embedded_field_2.should == pub_e2.embedded_field_2
            sub_e2.embedded_field_3.should == pub_e2.embedded_field_3
          end
        end
      end

      context 'when the parent already exists' do
        it 'replicates' do
          pub = PublisherModelEmbedMany.create(:field_1 => '1')

          eventually do
            SubscriberModelEmbedMany.first.should_not == nil
          end

          pub.models_embedded.create(:embedded_field_1 => 'e1', :embedded_field_2 => 'e2')
          pub.models_embedded.create(:embedded_field_1 => 'e3', :embedded_field_2 => 'e4')

          pub_e1 = pub.models_embedded[0]
          pub_e2 = pub.models_embedded[1]

          eventually do
            sub = SubscriberModelEmbedMany.first
            sub_e1 = sub.models_embedded[0]
            sub_e2 = sub.models_embedded[1]
            sub.id.should == pub.id
            sub.field_1.should == pub.field_1
            sub.field_2.should == pub.field_2
            sub.field_3.should == pub.field_3

            sub_e1.id.should == pub_e1.id
            sub_e1.embedded_field_1.should == pub_e1.embedded_field_1
            sub_e1.embedded_field_2.should == pub_e1.embedded_field_2
            sub_e1.embedded_field_3.should == pub_e1.embedded_field_3

            sub_e2.id.should == pub_e2.id
            sub_e2.embedded_field_1.should == pub_e2.embedded_field_1
            sub_e2.embedded_field_2.should == pub_e2.embedded_field_2
            sub_e2.embedded_field_3.should == pub_e2.embedded_field_3
          end
        end
      end
    end

    context 'when updating' do
      it 'replicates' do
        pub = PublisherModelEmbedMany.create(:field_1 => '1',
                                             :models_embedded => [{ :embedded_field_1 => 'e1',
                                                                    :embedded_field_2 => 'e2' },
                                                                  { :embedded_field_1 => 'e3',
                                                                    :embedded_field_2 => 'e4' }])

        eventually do
          SubscriberModelEmbedMany.first.should_not == nil
        end

        pub_e1 = pub.models_embedded[0]
        pub_e2 = pub.models_embedded[1]

        pub_e2.embedded_field_1 = 'e3_updated'
        pub_e2.save

        eventually do
          sub = SubscriberModelEmbedMany.first
          sub_e1 = sub.models_embedded[0]
          sub_e2 = sub.models_embedded[1]
          sub.id.should == pub.id
          sub.field_1.should == pub.field_1
          sub.field_2.should == pub.field_2
          sub.field_3.should == pub.field_3

          sub_e1.id.should == pub_e1.id
          sub_e1.embedded_field_1.should == pub_e1.embedded_field_1
          sub_e1.embedded_field_2.should == pub_e1.embedded_field_2
          sub_e1.embedded_field_3.should == pub_e1.embedded_field_3

          sub_e2.id.should == pub_e2.id
          sub_e2.embedded_field_1.should == pub_e2.embedded_field_1
          sub_e2.embedded_field_2.should == pub_e2.embedded_field_2
          sub_e2.embedded_field_3.should == pub_e2.embedded_field_3
        end
      end
    end

    context 'when destroying' do
      it 'replicates' do
        pub = PublisherModelEmbedMany.create(:field_1 => '1',
                                             :models_embedded => [{ :embedded_field_1 => 'e1',
                                                                    :embedded_field_2 => 'e2' },
                                                                  { :embedded_field_1 => 'e3',
                                                                    :embedded_field_2 => 'e4' }])

        eventually do
          sub = SubscriberModelEmbedMany.first
          sub.models_embedded[0].should_not == nil
          sub.models_embedded[1].should_not == nil
        end

        pub.models_embedded[1].destroy

        eventually do
          sub = SubscriberModelEmbedMany.first
          sub.models_embedded[0].should_not == nil
          sub.models_embedded[1].should     == nil
        end
      end
    end

    context 'when creating/updating/destroying' do
      it 'replicates' do
        pub = PublisherModelEmbedMany.create(:field_1 => '1',
                                             :models_embedded => [{ :embedded_field_1 => 'e1',
                                                                    :embedded_field_2 => 'e2' },
                                                                  { :embedded_field_1 => 'e3',
                                                                    :embedded_field_2 => 'e4' },
                                                                  { :embedded_field_1 => 'e5',
                                                                    :embedded_field_2 => 'e6' }])

        eventually do
          SubscriberModelEmbedMany.first.should_not == nil
        end

        pub_e1 = pub.models_embedded[0]
        pub_e2 = pub.models_embedded[1]
        pub_e3 = pub.models_embedded[2]

        # Updating the first one, Destroying the second one, and adding a new one
        pub_e2.destroy
        pub_e1.embedded_field_1 = 'e1_updated'
        pub_e1.save
        pub.models_embedded.create(:embedded_field_1 => 'e7', :embedded_field_2 => 'e8')

        pub_e1 = pub.models_embedded[0]
        pub_e2 = pub.models_embedded[1]
        pub_e3 = pub.models_embedded[2]

        eventually do
          sub = SubscriberModelEmbedMany.first
          sub.models_embedded.size.should == 3
          sub_e1 = sub.models_embedded[0]
          sub_e2 = sub.models_embedded[1]
          sub_e3 = sub.models_embedded[2]
          sub.id.should == pub.id
          sub.field_1.should == pub.field_1
          sub.field_2.should == pub.field_2
          sub.field_3.should == pub.field_3

          sub_e1.id.should == pub_e1.id
          sub_e1.embedded_field_1.should == pub_e1.embedded_field_1
          sub_e1.embedded_field_2.should == pub_e1.embedded_field_2
          sub_e1.embedded_field_3.should == pub_e1.embedded_field_3

          sub_e2.id.should == pub_e2.id
          sub_e2.embedded_field_1.should == pub_e2.embedded_field_1
          sub_e2.embedded_field_2.should == pub_e2.embedded_field_2
          sub_e2.embedded_field_3.should == pub_e2.embedded_field_3

          sub_e3.id.should == pub_e3.id
          sub_e3.embedded_field_1.should == pub_e3.embedded_field_1
          sub_e3.embedded_field_2.should == pub_e3.embedded_field_2
          sub_e3.embedded_field_3.should == pub_e3.embedded_field_3
        end
      end
    end
  end
end
