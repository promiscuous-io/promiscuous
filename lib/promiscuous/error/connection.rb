class Promiscuous::Error::Connection < RuntimeError
  attr_accessor :service, :url

  def initialize(options={})
    super(nil)
    self.service = options[:service]
    self.url = Promiscuous::Config.__send__("#{service}_url")
  end

  def message
    "Lost connection with #{url}"
  end

  def to_s
    message
  end
end
