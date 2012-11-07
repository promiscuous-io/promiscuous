require 'spec_helper'

describe Promiscuous::Subscriber, '.subscriber_class_for' do
  let(:base) { Promiscuous::Subscriber::Base }
  context 'when the payload is a string' do
    it 'returns the correct subscriber' do
      subject.subscriber_class_for("string").should == base
    end
  end

  context 'when the payload is an integer' do
    it 'returns the correct subscriber' do
      subject.subscriber_class_for(1).should == base
    end
  end

  context 'when the payload is a hash without the amqp key' do
    it 'returns the correct subscriber' do
      subject.subscriber_class_for(:hash => 1).should == base
    end
  end

  context 'when the payload is an array' do
    it 'returns the correct subscriber' do
      subject.subscriber_class_for([1,2,3]).should == base
    end
  end
end
