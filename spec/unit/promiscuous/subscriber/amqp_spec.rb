require 'spec_helper'

describe Promiscuous::Subscriber::AMQP, '.subscriber_key' do
  context 'when the payload is a string' do
    it 'returns the correct subscriber' do
      subject.subscriber_key("string").should be_nil
    end
  end

  context 'when the payload is an integer' do
    it 'returns the correct subscriber' do
      subject.subscriber_key(1).should be_nil
    end
  end

  context 'when the payload is a hash without the amqp key' do
    it 'returns the correct subscriber' do
      subject.subscriber_key(:hash => 1).should be_nil
    end
  end

  context 'when the payload is an array' do
    it 'returns the correct subscriber' do
      subject.subscriber_key([1,2,3]).should be_nil
    end
  end
end
