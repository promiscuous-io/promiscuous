class Promiscuous::Ephemeral
  def initialize(attributes)
    attributes.each { |k, v| self.__send__("#{k}=", v) }
  end

  def self.create(attributes)
    new(attributes).tap { |m| m.save }
  end

  def save
    self.class.promiscuous_publisher.new(:instance => self).publish
  end
end
