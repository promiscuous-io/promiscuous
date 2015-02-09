module BothHelper
  def both_after_use_real_backend
    bunny_after_use_real_backend
    # poseidon_after_use_real_backend
  end
end

RSpec.configure do |config|
  config.before do
    # $tc ||= TestCluster.new
    # $tc.start
  end

  config.after do
    # $tc.stop
  end
end
