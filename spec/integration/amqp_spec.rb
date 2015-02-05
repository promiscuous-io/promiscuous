require 'spec_helper'

if Promiscuous::Config.backend == :bunny
  describe Promiscuous::Backend::Bunny do
    before { use_real_backend }

    it 'handles frame sized payloads' do
      Promiscuous::Backend::Bunny.publish(:exchange => Promiscuous::Config.publisher_exchange, :key => 'ohai', :payload => '*' * 131063)
      Promiscuous::Backend::Bunny.publish(:exchange => Promiscuous::Config.publisher_exchange, :key => 'ohai', :payload => '*' * 131064)
      Promiscuous::Backend::Bunny.publish(:exchange => Promiscuous::Config.publisher_exchange, :key => 'ohai', :payload => '*' * 131065)
    end
  end
end
