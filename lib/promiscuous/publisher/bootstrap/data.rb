require 'ruby-progressbar'

class Promiscuous::Publisher::Bootstrap::Data
  class << self
    def setup(options={})
      range_redis_keys.each { |key| redis.del(key) }

      models    = options[:models]
      models   ||= Promiscuous::Publisher::Model.publishers.values
      .reject { |publisher| publisher.include? Promiscuous::Publisher::Model::Ephemeral }
      .reject { |publisher| publisher.publish_to =~ /^__promiscuous__\// }

      models.each { |model| create_range(model, options) }
    end

    def start
      connection   = Promiscuous::Publisher::Bootstrap::Connection.new

      range_redis_keys.each do |key|
        lock = Promiscuous::Redis::Mutex.new(key, lock_options)
        if lock.try_lock
          unless redis.hget(key, 'completed') == "true"
            selector = JSON.parse(redis.hget(key, 'selector'))
            options  = JSON.parse(redis.hget(key, 'options'))
            klass    = redis.hget(key, 'class').constantize
            start    = Time.parse(redis.hget(key, 'start'))
            finish   = Time.parse(redis.hget(key, 'finish'))

            range_selector(klass, selector, options, start, finish).each do |instance|
              publish_data(connection, instance)
              # TODO lock.extend
            end
            redis.hset(key, 'completed', true)
            lock.unlock
            break
          end
        end
      end
    end

    private

    def create_range(model, options)
      range_size = options[:range_size] || 1000

      without_promiscuous do
        count = model.all.count
        return if count == 0

        num_ranges = (count/range_size.to_f).ceil
        first      = id_time(model, 1)
        last       = id_time(model, -1) + 2.seconds
        increment  = ((last - first)/num_ranges).ceil

        range_start = first
        num_ranges.times do |i|
          range_start  = range_start + increment * i
          range_finish = range_start + increment

          redis.multi do
            key = range_redis_key.join(i)
            redis.hset(key, 'selector', model.all.selector.to_json)
            redis.hset(key, 'options', model.all.options.to_json)
            redis.hset(key, 'class', model.all.klass.to_s)
            redis.hset(key, 'start', range_start)
            redis.hset(key, 'finish', range_finish)
            redis.hset(key, 'completed', 'false')
          end
        end
      end
    end

    def range_selector(klass, selector, options, start_time, finish_time)
      criteria = Mongoid::Criteria.new(klass)
      criteria.selector = selector
      criteria.options = options

      criteria.order_by("$natural" =>  1).where(:_id.gte => Moped::BSON::ObjectId.from_time(start_time),
                                             :_id.lt =>  Moped::BSON::ObjectId.from_time(finish_time))
    end

    def range_redis_key
      Promiscuous::Key.new(:pub).join('bootstrap:range')
    end

    def range_redis_keys
      redis.keys("#{range_redis_key}*").reject { |k| k =~ /lock$/ }
    end

    def lock_options
      @@lock_options ||= {
        :timeout  => 10.seconds,
        :sleep    => 0.01.seconds,
        :expire   => 5.minutes,
        :lock_set => Promiscuous::Key.new(:pub).join('bootstrap_lock_set').to_s,
        :node     => redis
      }
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
