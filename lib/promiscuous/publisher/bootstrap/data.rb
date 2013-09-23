require 'ruby-progressbar'

class Promiscuous::Publisher::Bootstrap::Data < Promiscuous::Publisher::Bootstrap::Base
  def initialize(options={})
    @concurrency = options[:concurrency] || 1
    @models     = options[:models]
    @models   ||= Promiscuous::Publisher::Model.publishers.values
                  .reject { |publisher| publisher.include? Promiscuous::Publisher::Model::Ephemeral }
                  .reject { |publisher| publisher.publish_to =~ /^__promiscuous__\// }
  end

  def lock_options
    @@lock_options ||= {
      :timeout  => 1.year,   # wait forever.
      :sleep    => 1.second, # polling every second. No need to be aggressive, it would distrub real traffic.
      :expire   => 1.minute, # after one minute, we are considered dead
      :lock_set => Promiscuous::Key.new(:pub).join('lock_set').to_s
    }
  end

  def _bootstrap
    # XXX Running without_promiscuous to ensure we are not running within a
    # context. Running within a context causes a memory leak when iterating
    # though the entire collection.
    without_promiscuous do
      @models.each do |model|
        count = model.all.count
        return if count == 0

        first     = model.order_by("$natural" =>  1).only(:id).limit(1).first.id.generation_time
        last      = model.order_by("$natural" => -1).only(:id).limit(1).first.id.generation_time + 2.seconds
        increment = ((last - first)/@concurrency).ceil

        bar     = ProgressBar.create(:format => '%t |%b>%i| %c/%C %e', :title => "Bootstrapping #{model}", :total => count)
        threads = []
        @concurrency.times do |thread|
          threads << Thread.new(thread, first) do |i, block_start|
            block_start = block_start + increment * i
            block_end   = block_start + increment

            # TODO Abstract DB operation (make it work with sequence numbers for sql)
            model.order_by("$natural" =>  1).where(:_id.gte => Moped::BSON::ObjectId.from_time(block_start), :_id.lt => Moped::BSON::ObjectId.from_time(block_end)).each do |instance|
              dep = instance.promiscuous.tracked_dependencies.first
              dep.version = instance[Promiscuous::Publisher::Operation::Base::VERSION_FIELD].to_i
              payload = instance.promiscuous.payload
              payload[:operation] = :bootstrap_data
              payload[:dependencies] = {:write => [dep]}
              self.publish(:key => payload[:__amqp__], :payload => MultiJson.dump(payload))
              bar.increment
            end
          end
        end
        threads.each(&:join)
      end
    end
  end
end
