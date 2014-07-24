require 'active_record'

if ENV['LOGGER_LEVEL']
  ActiveRecord::Base.logger = Logger.new(STDERR)
  ActiveRecord::Base.logger.level = ENV['LOGGER_LEVEL'].to_i
end

db_settings = {
  :adapter  => "mysql2",
  :database => "promiscuous",
  :username => "root",
  :password => nil,
  :encoding => "utf8",
  :pool => 20,
}

ActiveRecord::Base.establish_connection(db_settings.merge('database' => 'mysql'))
ActiveRecord::Base.connection.drop_database(db_settings[:database]) rescue nil
ActiveRecord::Base.connection.create_database(db_settings[:database])
ActiveRecord::Base.establish_connection(db_settings)

load 'spec/spec_helper/sql.rb'
