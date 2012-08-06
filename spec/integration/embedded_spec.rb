require 'spec_helper'
require 'integration/models'
require 'replicable/worker'

describe Replicable do
  before { use_real_amqp }

  before do
    define_constant(:publisher_embeds, Replicable::Publisher) do
      publish :to => 'crowdtap/publisher_model_embeds',
              :model => PublisherModelEmbeds,
              :attributes => [:field_1, :field_2, :field_3, :model_embedded]
    end

    define_constant(:publisher_embedded, Replicable::Publisher) do
      publish :to => 'crowdtap/model_embedded',
              :model => PublisherModelEmbedded,
              :attributes => [:embedded_field_1, :embedded_field_2, :embedded_field_3]
    end

    define_constant(:subscriber_embeds, Replicable::Subscriber) do
      subscribe :from => 'crowdtap/publisher_model_embeds',
                :model => SubscriberModelEmbeds,
                :attributes => [:field_1, :field_2, :field_3, :model_embedded]
    end

    define_constant(:subscriber_embedded, Replicable::Subscriber) do
      subscribe :from => 'crowdtap/model_embedded',
                :model => SubscriberModelEmbedded,
                :attributes => [:embedded_field_1, :embedded_field_2, :embedded_field_3]
    end
  end

  before { Replicable::Worker.run }

  context 'when creating' do
    it 'replicates' do
      pub = PublisherModelEmbeds.create(:field_1 => '1',
                                        :model_embedded => { :embedded_field_1 => 'e1',
                                                             :embedded_field_2 => 'e2' })
      pub_e = pub.model_embedded

      eventually do
        sub = SubscriberModelEmbeds.first
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
    it 'replicates' do
      pub = PublisherModelEmbeds.create(:field_1 => '1',
                                        :model_embedded => { :embedded_field_1 => 'e1',
                                                             :embedded_field_2 => 'e2' })
      pub.update_attributes(:field_1 => '1_updated',
                            :model_embedded => { :embedded_field_1 => 'e1_updated',
                                                 :embedded_field_2 => 'e2_updated' })
      pub_e = pub.model_embedded

      eventually do
        sub = SubscriberModelEmbeds.first
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

  context 'when destroying' do
    it 'replicates' do
      pub = PublisherModelEmbeds.create(:field_1 => '1',
                                        :model_embedded => { :embedded_field_1 => 'e1',
                                                             :embedded_field_2 => 'e2' })

      eventually do
        eventually { SubscriberModelEmbeds.count.should == 1 }
        pub.destroy
        eventually { SubscriberModelEmbeds.count.should == 0 }
      end
    end
  end

  after do
    Replicable::AMQP.close
    Replicable::Subscriber.subscriptions.clear
  end
end
