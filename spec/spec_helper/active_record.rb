require 'active_record'

if ENV['LOGGER_LEVEL']
  ActiveRecord::Base.logger = Logger.new(STDERR)
  ActiveRecord::Base.logger.level = ENV['LOGGER_LEVEL'].to_i
end

db_settings = {
  :adapter  => RUBY_PLATFORM == "java" ? "jdbcpostgresql" : "postgresql",
  :database => "promiscuous",
  :username => "postgres",
  :password => nil,
  :encoding => "utf8",
  :pool => 20,
}

ActiveRecord::Base.establish_connection(db_settings.merge('database' => 'postgres'))
ActiveRecord::Base.connection.drop_database(db_settings[:database]) rescue nil
ActiveRecord::Base.connection.create_database(db_settings[:database])


class PromiscuousMigration < ActiveRecord::Migration
  def change
    [:publisher_models, :publisher_model_others,
     :subscriber_models, :subscriber_model_others,
     :publisher_dsl_models, :subscriber_dsl_models,
     :publisher_another_dsl_models, :subscriber_another_dsl_models,
     :publisher_model_without_subscribers].each do |table|
      create_table table, :force => true do |t|
        t.string :field_1
        t.string :field_2
        t.string :field_3
        t.string :child_field_1
        t.string :child_field_2
        t.string :child_field_3
        t.integer :publisher_id
        t.integer :_v, :limit => 8, :default => 1
      end

      create_table :publisher_model_belongs_tos, :force => true do |t|
        t.integer :publisher_model_id
        t.integer :_v, :limit => 8, :default => 1
      end

      create_table :subscriber_model_belongs_tos, :force => true do |t|
        t.integer :publisher_model_id
        t.integer :_v, :limit => 8
      end

      create_table :_promiscuous, :force => true do |t|
        t.string    :batch
        t.timestamp :at, :default => :now
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
    DatabaseCleaner.clean rescue nil
  end
end
