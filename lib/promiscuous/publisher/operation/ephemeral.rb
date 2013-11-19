class Promiscuous::Publisher::Operation::Ephemeral < Promiscuous::Publisher::Operation::Atomic
  def execute
    super {}
  end

  def yell_about_missing_instance
    # don't yell :)
  end

  def self.recover_operation(*recovery_payload)
    # no instance when we recover, it's okay
    new(:instance => nil)
  end
end
