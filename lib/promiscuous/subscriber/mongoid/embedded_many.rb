class Promiscuous::Subscriber::Mongoid::EmbeddedMany < Promiscuous::Subscriber::Base
  include Promiscuous::Subscriber::AMQP

  subscribe :from => '__promiscuous__/embedded_many'

  def old_embeddeds
    options[:old_value]
  end

  def parent
    options[:parent]
  end

  alias :new_embeddeds :payload

  def process
    # XXX Reordering is not supported

    # find all updatable docs
    new_embeddeds.each do |new_e|
      old_e = old_embeddeds.select { |e| e.id.to_s == new_e['id'] }.first
      if old_e
        new_e['existed'] = true
        old_e.instance_variable_set(:@keep, true)
        Promiscuous::Subscriber.process(new_e, :old_value => old_e)
      end
    end

    # delete all the old ones
    old_embeddeds.each do |old_e|
      old_e.destroy unless old_e.instance_variable_get(:@keep)
    end

    # create all the new ones
    new_embeddeds.reject { |new_e| new_e['existed'] }.each do |new_e|
      new_e_instance = Promiscuous::Subscriber.process(new_e)
      parent.__send__(old_embeddeds.metadata[:name]) << new_e_instance
    end
  end

  def instance
    raise Promiscuous::Subscriber::Attributes::DontUpdate.new
  end
end
