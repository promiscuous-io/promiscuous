require 'spec_helper'

describe Promiscuous::AMQP do
  before { use_real_backend }

  it 'handles frame sized payloads' do
    Promiscuous::AMQP.publish(:key => 'ohai', :payload => '*' * 131063)
    Promiscuous::AMQP.publish(:key => 'ohai', :payload => '*' * 131064)
    Promiscuous::AMQP.publish(:key => 'ohai', :payload => '*' * 131065)
  end
end
