require 'spec_helper'

if ORM.has(:many_embedded_documents)
  describe Promiscuous do
    before { load_models }
    before { use_real_backend }
    before { run_subscriber_worker! }

    context 'when creating' do
      context 'when the parent does not exist yet' do
        it 'replicates' do
          pub = nil
          Promiscuous.transaction do
            pub = PublisherModelEmbedMany.create(:field_1 => '1',
                                                 :models_embedded => [{ :embedded_field_1 => 'e1',
                                                                        :embedded_field_2 => 'e2' },
                                                                      { :embedded_field_1 => 'e3',
                                                                        :embedded_field_2 => 'e4' }])
          end
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
          pub = Promiscuous.transaction { PublisherModelEmbedMany.create(:field_1 => '1') }

          eventually do
            SubscriberModelEmbedMany.first.should_not == nil
          end

          Promiscuous.transaction do
            pub.models_embedded.create(:embedded_field_1 => 'e1', :embedded_field_2 => 'e2')
            pub.models_embedded.create(:embedded_field_1 => 'e3', :embedded_field_2 => 'e4')
          end

          pub.reload
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
        pub = nil
        Promiscuous.transaction do
          pub = PublisherModelEmbedMany.create(:field_1 => '1',
                                               :models_embedded => [{ :embedded_field_1 => 'e1',
                                                                      :embedded_field_2 => 'e2' },
                                                                    { :embedded_field_1 => 'e3',
                                                                      :embedded_field_2 => 'e4' }])
        end

        eventually do
          SubscriberModelEmbedMany.first.should_not == nil
        end

        pub_e1 = pub.models_embedded[0]
        pub_e2 = pub.models_embedded[1]

        Promiscuous.transaction do
          pub_e2.embedded_field_1 = 'e3_updated'
          pub_e2.save
        end

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
        pub = nil
        Promiscuous.transaction do
          pub = PublisherModelEmbedMany.create(:field_1 => '1',
                                               :models_embedded => [{ :embedded_field_1 => 'e1',
                                                                      :embedded_field_2 => 'e2' },
                                                                    { :embedded_field_1 => 'e3',
                                                                      :embedded_field_2 => 'e4' }])
        end

        eventually do
          sub = SubscriberModelEmbedMany.first
          sub.models_embedded[0].should_not == nil
          sub.models_embedded[1].should_not == nil
        end

        # XXX Mongoid is buggy
        Promiscuous.transaction(:active => true) { pub.models_embedded[1].destroy }

        eventually do
          sub = SubscriberModelEmbedMany.first
          sub.models_embedded[0].should_not == nil
          sub.models_embedded[1].should     == nil
        end
      end
    end

    context 'when creating/updating/destroying' do
      it 'replicates' do
        pub = nil
        Promiscuous.transaction do
          pub = PublisherModelEmbedMany.create(:field_1 => '1',
                                               :models_embedded => [{ :embedded_field_1 => 'e1',
                                                                      :embedded_field_2 => 'e2' },
                                                                    { :embedded_field_1 => 'e3',
                                                                      :embedded_field_2 => 'e4' },
                                                                    { :embedded_field_1 => 'e5',
                                                                      :embedded_field_2 => 'e6' }])
        end

        eventually do
          SubscriberModelEmbedMany.first.should_not == nil
        end

        pub_e1 = pub.models_embedded[0]
        pub_e2 = pub.models_embedded[1]
        pub_e3 = pub.models_embedded[2]

        Promiscuous.transaction do
          # Updating the first one, Destroying the second one, and adding a new one
          pub_e2.destroy
          pub_e1.embedded_field_1 = 'e1_updated'
          pub_e1.save
          pub.models_embedded.create(:embedded_field_1 => 'e7', :embedded_field_2 => 'e8')
        end

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
