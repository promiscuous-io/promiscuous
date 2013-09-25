require 'ruby-progressbar'

class Promiscuous::Publisher::Bootstrap::Data
  class << self
    def setup(options={})
      range_redis_keys.each { |key| Promiscuous::Redis.master.del(key) }

      models    = options[:models]
      models   ||= Promiscuous::Publisher::Model.publishers.values
      .reject { |publisher| publisher.include? Promiscuous::Publisher::Model::Ephemeral }
      .reject { |publisher| publisher.publish_to =~ /^__promiscuous__\// }

      models.each { |model| create_range(model, options) }
    end

    def start
      max_attempts = 10
      connection   = Promiscuous::Publisher::Bootstrap::Connection.new
      tries        = 0

      loop do
        range_redis_keys.each do |key|
          if lock = Promiscuous::Redis::Mutex.new(key, lock_options).try_lock
            start  = Promiscuous::Redis.master.hget(key, 'start')
            finish = Promiscuous::Redis.master.hget(key, 'finish')

            range_selector(start, finish).each do |instance|
              publish_data(connection, instance)
              # lock.extend
            end
            Promiscuous::Redis.master.hset(key,'completed', true)
            lock.unlock
          end
          break if tries > max_attempts
          tries += 1
          sleep 1
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

          key = "#{range_redis_key}_#{i}"
          Promiscuous::Redis.master.hset(key, 'start', range_start)
          Promiscuous::Redis.master.hset(key, 'finish', range_finish)
          Promiscuous::Redis.master.hset(key, 'completed', false)
        end
      end
    end

    def range_selector(model, start_time, end_time)
      model.order_by("$natural" =>  1).where(:_id.gte => Moped::BSON::ObjectId.from_time(start_time),
                                             :_id.lt => Moped::BSON::ObjectId.from_time(end_time))
    end

    def range_redis_key
      Promiscuous::Key.new(:pub).join('bootstrap:range')
    end

    def range_redis_keys
      Promiscuous::Redis.master.keys("#{range_redis_key}*")
    end

    def lock_options
      @@lock_options ||= {
        :timeout  => 10.seconds,
        :sleep    => 0.01.seconds,
        :expire   => 5.minutes,
        :lock_set => Promiscuous::Key.new(:pub).join('bootstrap_lock_set').to_s,
        :node     => Promiscuous::Redis.master
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
  end
end
