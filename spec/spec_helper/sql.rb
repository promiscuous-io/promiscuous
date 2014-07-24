class PromiscuousMigration < ActiveRecord::Migration
  def change
    [:publisher_models, :publisher_model_others,
     :subscriber_models, :subscriber_model_others,
     :publisher_dsl_models, :subscriber_dsl_models,
     :publisher_another_dsl_models, :subscriber_another_dsl_models,
     :publisher_model_without_subscribers].each do |table|
      create_table table, :force => true do |t|
        t.string :unpublished
        t.string :field_1
        t.string :field_1_derived
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
        t.column    :at, 'TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP'
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
    without_promiscuous { DatabaseCleaner.clean }
    ActiveRecord::Base.connection_pool.disconnect!
  end
end
