require 'ruby-progressbar'

class Promiscuous::Publisher::Bootstrap::Data
  class << self
    def setup(options={})
      range_redis_keys.each { |key| redis.del(key) }

      models    = options[:models]
      models   ||= Promiscuous::Publisher::Model.publishers.values
      .reject { |publisher| publisher.include? Promiscuous::Publisher::Model::Ephemeral }
      .reject { |publisher| publisher.publish_to =~ /^__promiscuous__\// }

      models.each_with_index { |model, i| create_range(i, model, options) }
    end

    def start(options={})
      connection = Promiscuous::Publisher::Bootstrap::Connection.new

      range_redis_keys.each do |key|
        lock = Promiscuous::Redis::Mutex.new(key, lock_options(options[:lock]))
        if lock.try_lock
          if range = redis.get(key)
            range = MultiJson.load(range)
            selector = range['selector']
            options  = range['options']
            klass    = range['class'].constantize
            start    = Time.parse(range['start'])
            finish   = Time.parse(range['finish'])

            lock_extended_at = Time.now
            range_selector(klass, selector, options, start, finish).each_with_index do |instance, i|
              publish_data(connection, instance)
              if (Time.now - lock_extended_at) > lock_options[:expire]/5
                raise "Another worker stole your work!" unless lock.extend
              end
            end
            redis.del(key)
            lock.unlock
          end
        end
      end
    end

    private

    def create_range(namespace, model, options)
      range_size = options[:range_size] || 1000

      without_promiscuous do
        count = model.all.count
        return if count == 0

        num_ranges = (count/range_size.to_f).ceil
        first      = id_time(model, 1)
        last       = id_time(model, -1) + 2 # Ensure we capture all docs as $gte -> $lt is used
        increment  = ((last - first)/num_ranges).ceil

        num_ranges.times do |i|
          range_start  = first + (increment * i).seconds
          range_finish = range_start + increment.seconds

          key = range_redis_key.join(namespace).join(i)
          value = MultiJson.dump(:selector => model.all.selector,
                                 :options  => model.all.options,
                                 :class    => model.all.klass.to_s,
                                 :start    => range_start,
                                 :finish   => range_finish)
          redis.set(key, value)
        end
      end
    end

    def range_selector(klass, selector, options, start_time, finish_time)
      criteria = Mongoid::Criteria.new(klass)
      criteria.selector = selector
      criteria.options = options

      criteria.order_by("$natural" =>  1).where(:_id => { '$gte' =>  Moped::BSON::ObjectId.from_time(start_time),
                                                          '$lt'  =>  Moped::BSON::ObjectId.from_time(finish_time) })
    end

    def range_redis_key
      Promiscuous::Key.new(:pub).join('bootstrap:range')
    end

    def range_redis_keys
      redis.keys("#{range_redis_key}*").reject { |k| k =~ /lock$/ }.sort
    end

    def lock_options(options=nil)
      options ||= {}
      @@lock_options ||= {
        :timeout  => 10.seconds,
        :sleep    => 0.01.seconds,
        :expire   => 5.minutes,
        :node     => redis
      }.merge(options)
    end

    def publish_data(connection, instance)
      dep = instance.promiscuous.tracked_dependencies.first
      dep.version = instance[Promiscuous::Publisher::Operation::Base::VERSION_FIELD].to_i

      payload = instance.promiscuous.payload
      payload[:operation] = :bootstrap_data
      payload[:dependencies] = {:write => [dep]}

      connection.publish(:key => payload[:__amqp__], :payload => MultiJson.dump(payload))
    end

    def id_time(model, sort_order)
      model.order_by("$natural" =>  sort_order).only(:id).limit(1).first.id.generation_time
    end

    def redis
      Promiscuous::Redis.master.nodes.first
    end
  end
end
