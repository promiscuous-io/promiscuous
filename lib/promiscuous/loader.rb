module Promiscuous::Loader
  CONFIG_FILES = %w(config/publishers.rb config/subscribers.rb config/promiscuous.rb)

  def self.prepare
    CONFIG_FILES.each do |file_name|
      file = defined?(Rails) ?  Rails.root.join(file_name) : File.join('.', file_name)
      load file if File.exists?(file)
    end

    # A one shot recovery on boot
    if Promiscuous::Config.recovery_on_boot
      Promiscuous::Publisher::Worker.new.try_recover
    end
  end

  def self.cleanup
    Promiscuous::Publisher::Model.publishers.clear
    Promiscuous::Publisher::Model::Mongoid.collection_mapping.clear if defined?(Mongoid)
    Promiscuous::Subscriber::Model.mapping.select! { |k| k.to_s =~ /__promiscuous__/ }
  end
end
