require 'spec_helper'

describe Promiscuous::Redis do

  describe 'script' do
    let(:redis)  { subject.new_connection }
    let(:script) { Promiscuous::Redis::Script.new('return 123') }

    it 'reload the script if needed' do
      script.eval(redis).should == 123
      redis.script(:flush)
      script.eval(redis).should == 123
    end
  end
end
