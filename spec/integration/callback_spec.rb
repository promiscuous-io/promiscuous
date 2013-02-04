require 'spec_helper'

describe Promiscuous do
  before { load_models }
  before { use_real_backend }

  context "when using a vanilla model" do
    before { record_callbacks(SubscriberModel) }

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

    before { run_subscriber_worker! }

    context 'when creating' do
      it 'calls proper callbacks' do
        pub = PublisherModel.create
        eventually { SubscriberModel.callbacks(:id => pub.id).should == [:create, :save] }
      end
    end

    context 'when updating' do
      it 'calls proper callbacks' do
        pub = PublisherModel.create
        eventually { SubscriberModel.first.should_not == nil }

        clear_callbacks
        pub.update_attributes(:field_1 => '1')
        eventually { SubscriberModel.callbacks(:id => pub.id).should == [:update, :save] }
      end
    end

    context 'when destroying' do
      it 'calls proper callbacks' do
        pub = PublisherModel.create
        eventually { SubscriberModel.first.should_not == nil }

        clear_callbacks
        pub.destroy
        eventually { SubscriberModel.callbacks(:id => pub.id).should == [:destroy] }
      end
    end
  end

  if ORM.has(:embedded_documents)
    context 'when using embedded documents' do
      context 'when using one embedded document' do
        before { record_callbacks(PublisherModelEmbedded) }
        before { record_callbacks(SubscriberModelEmbedded) }

        before do
          define_constant('PublisherEmbed', ORM::PublisherBase) do
            publish :to => 'crowdtap/publisher_model_embed',
                    :class => :PublisherModelEmbed,
                    :attributes => [:field_1, :field_2, :field_3, :model_embedded]
          end

          define_constant('PublisherEmbedded', ORM::PublisherBase) do
            publish :to => 'crowdtap/model_embedded',
                    :class => :PublisherModelEmbedded,
                    :attributes => [:embedded_field_1, :embedded_field_2, :embedded_field_3]
          end

          define_constant('SubscriberEmbed', ORM::SubscriberBase) do
            subscribe :from => 'crowdtap/publisher_model_embed',
                      :class => SubscriberModelEmbed,
                      :attributes => [:field_1, :field_2, :field_3, :model_embedded]
          end

          define_constant('SubscriberEmbedded', ORM::SubscriberBase) do
            subscribe :from => 'crowdtap/model_embedded',
                      :class => SubscriberModelEmbedded,
                      :attributes => [:embedded_field_1, :embedded_field_2, :embedded_field_3]
          end
        end

        before { run_subscriber_worker! }

        context 'when creating' do
          it 'calls proper callbacks' do
            pub = PublisherModelEmbed.create(:model_embedded => { :embedded_field_1 => 'e1' })
            pub_e = pub.model_embedded
            eventually { SubscriberModelEmbedded.callbacks(:id => pub_e.id).should =~ [:create, :save] }
          end
        end

        context 'when replacing' do
          it 'calls proper callbacks' do
            pub = PublisherModelEmbed.create(:model_embedded => { :embedded_field_1 => 'e1' })
            eventually { SubscriberModelEmbed.first.should_not == nil }

            clear_callbacks
            pub.model_embedded = PublisherModelEmbedded.new
            pub_e = pub.model_embedded
            eventually { SubscriberModelEmbedded.callbacks(:id => pub_e.id).should =~ [:create, :save] }
          end
        end

        context 'when updating' do
          it 'calls proper callbacks' do
            pub = PublisherModelEmbed.create(:model_embedded => { :embedded_field_1 => 'e1' })
            eventually { SubscriberModelEmbed.first.should_not == nil }

            clear_callbacks
            pub_e = pub.model_embedded
            pub_e.update_attributes(:embedded_field_1 => 'updated')
            eventually { SubscriberModelEmbedded.callbacks(:id => pub_e.id).should =~ [:update, :save] }
          end
        end

        context 'when destroying' do
          it 'calls proper callbacks' do
            pub = PublisherModelEmbed.create(:model_embedded => { :embedded_field_1 => 'e1' })
            eventually { SubscriberModelEmbed.first.should_not == nil }

            clear_callbacks
            pub.destroy
            pub_e = pub.model_embedded
            eventually { SubscriberModelEmbedded.callbacks(:id => pub_e.id).should == [:destroy] }
          end
        end
      end
    end
  end

  if ORM.has(:many_embedded_documents)
    context 'when using many embedded documents' do
      before { record_callbacks(SubscriberModelEmbedded) }

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

      before { run_subscriber_worker! }

      context 'when creating' do
        it 'calls proper callbacks' do
          pub = PublisherModelEmbedMany.create(:models_embedded => [{:embedded_field_1 => 'e1'}])
          pub_e1 = pub.models_embedded[0]
          eventually { SubscriberModelEmbedded.callbacks(:id => pub_e1.id).should =~ [:create, :save] }
        end
      end

      context 'when appending' do
        it 'calls proper callbacks' do
          pub = PublisherModelEmbedMany.create(:models_embedded => [{:embedded_field_1 => 'e1'}])
          eventually { SubscriberModelEmbedMany.first.should_not == nil }
          clear_callbacks

          pub_e2 = pub.models_embedded.create(:embedded_field_1 => 'e2')
          eventually { SubscriberModelEmbedded.callbacks(:id => pub_e2.id).should =~ [:create, :save] }
        end
      end

      context 'when updating' do
        it 'calls proper callbacks' do
          pub = PublisherModelEmbedMany.create(:models_embedded => [{:embedded_field_1 => 'e1'}])
          eventually { SubscriberModelEmbedMany.first.should_not == nil }
          clear_callbacks

          pub_e1 = pub.models_embedded[0]
          pub_e1.update_attributes(:embedded_field_1 => 'e1_updated')
          eventually { SubscriberModelEmbedded.callbacks(:id => pub_e1.id).should =~ [:update, :save] }
        end
      end

      context 'when destroying' do
        it 'calls proper callbacks' do
          pub = PublisherModelEmbedMany.create(:models_embedded => [{:embedded_field_1 => 'e1'}])
          eventually { SubscriberModelEmbedMany.first.should_not == nil }
          clear_callbacks

          pub_e1 = pub.models_embedded[0]
          pub_e1.destroy
          eventually { SubscriberModelEmbedded.callbacks(:id => pub_e1.id).should == [:destroy] }
        end
      end

      context 'when creating/updating/destroying' do
          it 'calls proper callbacks' do
          pub = PublisherModelEmbedMany.create(:models_embedded => [{},{},{}])
          eventually { SubscriberModelEmbedMany.first.should_not == nil }
          clear_callbacks

          pub_e1 = pub.models_embedded[0]
          pub_e2 = pub.models_embedded[1]
          pub_e3 = pub.models_embedded[2]

          # Updating the first one, Destroying the second one, and adding a new one
          pub_e2.destroy
          pub_e1.embedded_field_1 = 'e1_updated'
          pub_e1.save
          pub_e4 = pub.models_embedded.create

          eventually do
            SubscriberModelEmbedded.callbacks(:id => pub_e1.id).should =~ [:update, :save]
            SubscriberModelEmbedded.callbacks(:id => pub_e2.id).should =~ [:destroy]
            SubscriberModelEmbedded.callbacks(:id => pub_e4.id).should =~ [:create, :save]
          end
        end
      end
    end
  end
end
