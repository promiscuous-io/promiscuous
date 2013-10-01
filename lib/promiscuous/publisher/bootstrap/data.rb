class Promiscuous::Publisher::Bootstrap::Data
  class << self
    def setup(options={})
      Promiscuous::Publisher::Bootstrap::Status.reset
      range_redis_keys.each { |key| redis.del(key) }

      models    = options[:models]
      models   ||= Promiscuous::Publisher::Model.publishers.values
      .reject { |publisher| publisher.include? Promiscuous::Publisher::Model::Ephemeral }
      .reject { |publisher| publisher.publish_to =~ /^__promiscuous__\// }

      models.each_with_index do |model, i|
        create_range(i, model, options)
        Promiscuous::Publisher::Bootstrap::Status.total(model.count)
      end
    end

    def run(options={})
      connection = Promiscuous::Publisher::Bootstrap::Connection.new

      range_redis_keys.each do |key|
        lock = Promiscuous::Redis::Mutex.new(key, lock_options(options[:lock]))
        if lock.try_lock
          if range = redis.get(key)
            range = MultiJson.load(range)
            selector = range['selector']
            options  = range['options']
            klass    = range['class'].constantize
            start    = range['start'].to_i
            finish   = range['finish'].to_i

            lock_extended_at = Time.now
            range_selector(klass, selector, options, start, finish).each_with_index do |instance, i|
              publish_data(connection, instance)

              if (Time.now - lock_extended_at) > lock_options[:expire]/5
                raise "Another worker stole your work!" unless lock.extend
                lock_extended_at = Time.now
              end
              Promiscuous::Publisher::Bootstrap::Status.inc
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
        first, last = min_max(model).map { |id| id.to_s.to_i(16) }
        last += 10 # Ensure that we capture the last ID based on BSON encoding
        increment  = ((last - first)/num_ranges).ceil

        num_ranges.times do |i|
          range_start  = first + (increment * i)
          range_finish = range_start + increment

          key = range_redis_key.join(namespace).join(i)
          value = MultiJson.dump(:selector => model.all.selector,
                                 :options  => model.all.options,
                                 :class    => model.all.klass.to_s,
                                 :start    => range_start.to_s,
                                 :finish   => range_finish.to_s)
          redis.set(key, value)
        end
      end
    end

    def range_selector(klass, selector, options, start, finish)
      option ||= {}
      criteria = Mongoid::Criteria.new(klass)
      criteria.selector = selector
      criteria.options = options.merge(:timeout => false)

      criteria.order_by("$natural" =>  1).where(:_id => { '$gte' =>  BSON::ObjectId.from_string(start.to_s(16)),
                                                          '$lt'  =>  BSON::ObjectId.from_string(finish.to_s(16)) })
    end

    def range_redis_key
      Promiscuous::Key.new(:pub).join('bootstrap:range')
    end

    def range_redis_keys
      redis.keys("#{range_redis_key}*").reject { |k| k =~ /:lock$/ }.sort
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

    def min_max(model)
      query = proc { |sort_order| model.order_by("_id" =>  sort_order).only(:id).limit(1).first.id }
      [query.call(1), query.call(-1)]
    end

    def redis
      Promiscuous::Redis.master.nodes.first
    end
  end
end
