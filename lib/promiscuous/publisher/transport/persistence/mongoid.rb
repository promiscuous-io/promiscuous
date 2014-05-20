class Promiscuous::Publisher::Transport::Persistence::Mongoid
  def save(batch)
    doc = Storage.create(:batch => batch.dump)
    batch.id = doc.id
  end

  def expired
    Storage.where(:at.lt => Time.now.utc - Promiscuous::Config.recovery_timeout.seconds).map { |doc| [doc.id, doc.batch] }
  end

  def delete(batch)
    Storage.find(batch.id).destroy
  end

  class Storage
    include Mongoid::Document
    store_in collection: Promiscuous::Config.transport_collection

    field :batch
    field :at, :type => Time, :default => -> { Time.now.utc }
  end
end
