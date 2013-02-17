require 'spec_helper'

describe Promiscuous do
  before { use_real_backend }

  if ORM.has(:mongoid)
    context 'when doing parallel increments' do
      before do
        define_constant :Publisher do
          include Mongoid::Document
          include Promiscuous::Publisher
          publish { field :field }
        end

        define_constant :Subscriber do
          include Mongoid::Document
          include Promiscuous::Subscriber
          subscribe(:from => '*/publisher') { field :field }
          field :inc_by_one
          before_update { inc(:inc_by_one, 1) if field == field_was + 1 }
        end

        run_subscriber_worker!
      end

      it 'stays ordered' do
        pub = Publisher.create(:field => 0)
        10.times.map { Thread.new { 10.times { pub.inc(:field, 1) } } }.each(&:join)
        eventually do
          Subscriber.first.field.should == 100
          Subscriber.first.inc_by_one.should == 100
        end
      end
    end
  end
end
