require 'active_record'

if ENV['LOGGER_LEVEL']
  ActiveRecord::Base.logger = Logger.new(STDERR)
  ActiveRecord::Base.logger.level = ENV['LOGGER_LEVEL'].to_i
end

ActiveRecord::Base.establish_connection(
  :adapter  => "postgresql",
  :database => "promiscuous",
  :username => ENV["TRAVIS"] ? "postgres" : "promiscuous",
  :password => ENV["TRAVIS"] ?        nil : "promiscuous",
  :encoding => "utf8"
)

class PromiscuousMigration < ActiveRecord::Migration
  def change
    [:publisher_models, :publisher_model_others,
     :subscriber_models, :subscriber_model_others].each do |table|
      create_table table, :force => true do |t|
        t.string :field_1
        t.string :field_2
        t.string :field_3
        t.string :child_field_1
        t.string :child_field_2
        t.string :child_field_3
        t.integer :publisher_id
      end
    end
  end

  migrate :up
end

DatabaseCleaner.strategy = :truncation

RSpec.configure do |config|
  config.before(:each) do
    DatabaseCleaner.start
  end

  config.after(:each) do
    DatabaseCleaner.clean
  end
end
