require 'spec_helper'

module AMQ
  module Client
    module Async
      class EventMachineClient < EM::Connection

        def force_connection_failure
          @tcp_connection_established = false
          @intentionally_closing_connection = false
          @tcp_connection_failed = true

          self.tcp_connection_lost
        end

      end
    end
  end
end

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

  context 'when there is a connection interruption' do
    it 'gracefully reconnects' do
      pub = PublisherModel.new(:field_1 => '1', :field_2 => '2', :field_3 => '3')
      pub.save

      Promiscuous::AMQP::RubyAMQP.channel.connection.force_connection_failure

      eventually do
        sub = SubscriberModel.first
        sub.id.should == pub.id
        sub.field_1.should == pub.field_1
        sub.field_2.should == pub.field_2
        sub.field_3.should == pub.field_3
      end
    end
  end
end
