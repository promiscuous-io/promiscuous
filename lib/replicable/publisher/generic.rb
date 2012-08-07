require 'replicable/publisher/class_bind'
require 'replicable/publisher/base'
require 'replicable/publisher/attributes'
require 'replicable/publisher/polymorphic'
require 'replicable/publisher/amqp'

class Replicable::Publisher::Generic < Replicable::Publisher::Base
  include Replicable::Publisher::ClassBind
  include Replicable::Publisher::Attributes
  include Replicable::Publisher::Polymorphic
  include Replicable::Publisher::AMQP
  include Replicable::Publisher::Descriptor
end
