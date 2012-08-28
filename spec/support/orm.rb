module ORM
  def self.has(feature)
    {
      :active_record      => [:active_record],
      :mongoid            => [:mongoid2, :mongoid3],
      :polymorphic        => [:mongoid2, :mongoid3],
      :embedded_documents => [:mongoid2, :mongoid3]
    }[feature].any? { |orm| orm.to_s == ENV['TEST_ENV'] }
  end

  if has(:mongoid)
    PublisherBase  = Promiscuous::Publisher::Mongoid
    SubscriberBase = Promiscuous::Subscriber::Mongoid
    ID = :_id
  elsif has(:active_record)
    PublisherBase  = Promiscuous::Publisher::ActiveRecord
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
