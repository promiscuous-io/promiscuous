require 'spec_helper'

if ORM.has(:embedded_documents)
  describe Promiscuous do
    before { load_models }
    before { use_real_backend }
    before { run_subscriber_worker! }

    context 'when creating' do
      it 'replicates' do
        pub = nil
        Promiscuous.context do
          pub = PublisherModelEmbed.create(:field_1 => '1',
                                           :model_embedded => { :embedded_field_1 => 'e1',
                                                                :embedded_field_2 => 'e2' })
        end
        pub_e = pub.model_embedded

        eventually do
          sub = SubscriberModelEmbed.first
          sub_e = sub.model_embedded
          sub.id.should == pub.id
          sub.field_1.should == pub.field_1
          sub.field_2.should == pub.field_2
          sub.field_3.should == pub.field_3

          sub_e.id.should == pub_e.id
          sub_e.embedded_field_1.should == pub_e.embedded_field_1
          sub_e.embedded_field_2.should == pub_e.embedded_field_2
          sub_e.embedded_field_3.should == pub_e.embedded_field_3
        end
      end
    end

    context 'when updating' do
      context 'when embedded document is saved' do
        it 'replicates' do
          pub = pub_e = nil
          Promiscuous.context do
            pub = PublisherModelEmbed.create(:field_1 => '1',
                                             :model_embedded => { :embedded_field_1 => 'e1',
                                                                  :embedded_field_2 => 'e2' })
            pub_e = pub.model_embedded
            pub_e.embedded_field_1 = 'e1_updated'
            pub_e.save
          end

          eventually do
            sub = SubscriberModelEmbed.first
            sub.id.should == pub.id
            sub.field_1.should == pub.field_1
            sub.field_2.should == pub.field_2
            sub.field_3.should == pub.field_3

            sub_e = sub.model_embedded
            sub_e.id.should == pub_e.id
            sub_e.embedded_field_1.should == pub_e.embedded_field_1
            sub_e.embedded_field_2.should == pub_e.embedded_field_2
            sub_e.embedded_field_3.should == pub_e.embedded_field_3
          end
        end
      end

      context 'when embedded document setter is used' do
        it 'replicates' do
          pub = nil
          Promiscuous.context do
            pub = PublisherModelEmbed.create(:field_1 => '1',
                                             :model_embedded => { :embedded_field_1 => 'e1',
                                                                  :embedded_field_2 => 'e2' })
          end
          pub_e = pub.model_embedded

          eventually do
            sub = SubscriberModelEmbed.first
            sub.id.should == pub.id
            sub.field_1.should == pub.field_1
            sub.field_2.should == pub.field_2
            sub.field_3.should == pub.field_3

            sub_e = sub.model_embedded
            sub_e.id.should == pub_e.id
            sub_e.embedded_field_1.should == pub_e.embedded_field_1
            sub_e.embedded_field_2.should == pub_e.embedded_field_2
            sub_e.embedded_field_3.should == pub_e.embedded_field_3
          end

          Promiscuous.context do
            pub.model_embedded = PublisherModelEmbeddedChild.new(:embedded_field_1 => 'e1_updated')
            pub.save
          end

          pub_e = pub.model_embedded

          eventually do
            sub = SubscriberModelEmbed.first
            sub.id.should == pub.id
            sub.field_1.should == pub.field_1
            sub.field_2.should == pub.field_2
            sub.field_3.should == pub.field_3

            sub_e = sub.model_embedded
            sub_e.id.should == pub_e.id
            sub_e.embedded_field_1.should == pub_e.embedded_field_1
            sub_e.embedded_field_2.should == pub_e.embedded_field_2
            sub_e.embedded_field_3.should == pub_e.embedded_field_3
          end
        end
      end

      context 'when parent document is saved' do
        it 'replicates' do
          pub = nil
          Promiscuous.context do
            pub = PublisherModelEmbed.create(:field_1 => '1',
                                             :model_embedded => { :embedded_field_1 => 'e1',
                                                                  :embedded_field_2 => 'e2' })
            pub.update_attributes(:field_1 => '1_updated',
                                  :model_embedded => { :embedded_field_1 => 'e1_updated',
                                                       :embedded_field_2 => 'e2_updated' })
          end
          pub_e = pub.model_embedded

          eventually do
            sub = SubscriberModelEmbed.first
            sub.id.should == pub.id
            sub.field_1.should == pub.field_1
            sub.field_2.should == pub.field_2
            sub.field_3.should == pub.field_3

            sub_e = sub.model_embedded
            sub_e.id.should == pub_e.id
            sub_e.embedded_field_1.should == pub_e.embedded_field_1
            sub_e.embedded_field_2.should == pub_e.embedded_field_2
            sub_e.embedded_field_3.should == pub_e.embedded_field_3
          end
        end
      end
    end

    context 'when destroying' do
      context 'the parent' do
        it 'replicates' do
          pub = nil
          Promiscuous.context do
            pub = PublisherModelEmbed.create(:field_1 => '1',
                                             :model_embedded => { :embedded_field_1 => 'e1',
                                                                  :embedded_field_2 => 'e2' })
          end

          eventually { SubscriberModelEmbed.count.should == 1 }
          Promiscuous.context { pub.destroy }
          eventually { SubscriberModelEmbed.count.should == 0 }
        end
      end

      context 'the embedded document with destroy' do
        it 'replicates' do
          pub = nil
            Promiscuous.context do
            pub = PublisherModelEmbed.create(:field_1 => '1',
                                             :model_embedded => { :embedded_field_1 => 'e1',
                                                                  :embedded_field_2 => 'e2' })
          end

          eventually { SubscriberModelEmbed.first.model_embedded.should_not == nil }
          Promiscuous.context { pub.model_embedded.destroy }
          eventually { SubscriberModelEmbed.first.model_embedded.should == nil }
        end
      end

      context 'the embedded document with setting to nil' do
        it 'replicates' do
          pub = nil
          Promiscuous.context do
            pub = PublisherModelEmbed.create(:field_1 => '1',
                                             :model_embedded => { :embedded_field_1 => 'e1',
                                                                  :embedded_field_2 => 'e2' })
          end

          eventually { SubscriberModelEmbed.first.model_embedded.should_not == nil }
          Promiscuous.context do
            pub.model_embedded = nil
            pub.save
          end
          eventually { SubscriberModelEmbed.first.model_embedded.should == nil }
        end
      end
    end
  end
end
