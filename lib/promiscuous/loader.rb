module Promiscuous::Loader
  CONFIG_FILES = %w(config/publishers.rb config/subscribers.rb config/promiscuous.rb)

  def self.prepare
    CONFIG_FILES.each do |file_name|
      file = defined?(Rails) ?  Rails.root.join(file_name) : File.join('.', file_name)
      load file if File.exists?(file)
    end
  end

  def self.cleanup
    Promiscuous::Publisher::Model.publishers.clear
    Promiscuous::Subscriber::Model.mapping.select! { |k| k.to_s =~ /__promiscuous__/ }
  end
end
