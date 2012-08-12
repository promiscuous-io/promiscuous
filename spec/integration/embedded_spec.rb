require 'spec_helper'
require 'promiscuous/worker'

describe Promiscuous do
  before { load_models }
  before { use_real_amqp }

  before do
    define_constant('PublisherEmbed', Promiscuous::Publisher::Mongoid) do
      publish :to => 'crowdtap/publisher_model_embed',
              :class => PublisherModelEmbed,
              :attributes => [:field_1, :field_2, :field_3, :model_embedded]
    end

    define_constant('PublisherEmbedded', Promiscuous::Publisher::Mongoid) do
      publish :to => 'crowdtap/model_embedded',
              :class => PublisherModelEmbedded,
              :attributes => [:embedded_field_1, :embedded_field_2, :embedded_field_3]
    end

    define_constant('SubscriberEmbed', Promiscuous::Subscriber::Mongoid) do
      subscribe :from => 'crowdtap/publisher_model_embed',
                :class => SubscriberModelEmbed,
                :attributes => [:field_1, :field_2, :field_3, :model_embedded]
    end

    define_constant('SubscriberEmbedded', Promiscuous::Subscriber::Mongoid) do
      subscribe :from => 'crowdtap/model_embedded',
                :class => SubscriberModelEmbedded,
                :attributes => [:embedded_field_1, :embedded_field_2, :embedded_field_3]
    end
  end

  before { Promiscuous::Worker.replicate }

  context 'when creating' do
    it 'replicates' do
      pub = PublisherModelEmbed.create(:field_1 => '1',
                                       :model_embedded => { :embedded_field_1 => 'e1',
                                                            :embedded_field_2 => 'e2' })
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
        pub = PublisherModelEmbed.create(:field_1 => '1',
                                         :model_embedded => { :embedded_field_1 => 'e1',
                                                              :embedded_field_2 => 'e2' })
        pub_e = pub.model_embedded
        pub_e.embedded_field_1 = 'e1_updated'
        pub_e.save

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
        pub = PublisherModelEmbed.create(:field_1 => '1',
                                         :model_embedded => { :embedded_field_1 => 'e1',
                                                              :embedded_field_2 => 'e2' })
        pub.model_embedded = PublisherModelEmbeddedChild.new(:embedded_field_1 => 'e1_updated')
        pub.save

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
        pub = PublisherModelEmbed.create(:field_1 => '1',
                                         :model_embedded => { :embedded_field_1 => 'e1',
                                                              :embedded_field_2 => 'e2' })
        pub.update_attributes(:field_1 => '1_updated',
                              :model_embedded => { :embedded_field_1 => 'e1_updated',
                                                   :embedded_field_2 => 'e2_updated' })
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
        pub = PublisherModelEmbed.create(:field_1 => '1',
                                         :model_embedded => { :embedded_field_1 => 'e1',
                                                              :embedded_field_2 => 'e2' })

        eventually do
          eventually { SubscriberModelEmbed.count.should == 1 }
          pub.destroy
          eventually { SubscriberModelEmbed.count.should == 0 }
        end
      end
    end

    context 'the embedded document with destroy' do
      it 'replicates' do
        pub = PublisherModelEmbed.create(:field_1 => '1',
                                         :model_embedded => { :embedded_field_1 => 'e1',
                                                              :embedded_field_2 => 'e2' })

        eventually do
          eventually { SubscriberModelEmbed.first.model_embedded.should_not == nil }
          pub.model_embedded.destroy
          eventually { SubscriberModelEmbed.first.model_embedded.should == nil }
        end
      end
    end

    context 'the embedded document with setting to nil' do
      it 'replicates' do
        pub = PublisherModelEmbed.create(:field_1 => '1',
                                         :model_embedded => { :embedded_field_1 => 'e1',
                                                              :embedded_field_2 => 'e2' })

        eventually do
          eventually { SubscriberModelEmbed.first.model_embedded.should_not == nil }
          pub.model_embedded = nil
          pub.save
          eventually { SubscriberModelEmbed.first.model_embedded.should == nil }
        end
      end
    end
  end

  after do
    Promiscuous::AMQP.close
    Promiscuous::Subscriber::AMQP.subscribers.clear
  end
end
