module ORM
  def self.backend
    @backend ||= ENV['TEST_ENV'].to_sym
  end

  def self.has(feature)
    {
      :active_record           => [:active_record],
      :mongoid                 => [:mongoid3],
      :polymorphic             => [:mongoid3],
      :embedded_documents      => [:mongoid3],
      :many_embedded_documents => [:mongoid3],
      :versioning              => [:mongoid3],
      :find_and_modify         => [:mongoid3],
    }[feature].any? { |orm| orm == backend }
  end

  if has(:mongoid)
    Operation = Promiscuous::Publisher::Model::Mongoid::Operation
    SubscriberBase = Promiscuous::Subscriber::Mongoid
    ID = :_id
  elsif has(:active_record)
    Operation = Promiscuous::Publisher::Operation
    SubscriberBase = Promiscuous::Subscriber::ActiveRecord
    ID = :id
  end

  def self.generate_id
    if has(:mongoid)
      BSON::ObjectId.new
    else
      @ar_id ||= 10
      @ar_id += 1
      @ar_id
    end
  end
end
