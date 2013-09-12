require 'ruby-progressbar'

class Promiscuous::Publisher::Bootstrap::Data < Promiscuous::Publisher::Bootstrap::Base
  def initialize(options={})
    @models = options[:models]
    @models ||= Promiscuous::Publisher::Model.publishers.values
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
    @models.each do |model|
      # XXX Running without_promiscuous to ensure we are not running within a
      # context. Running within a context causes a memory leak when iterating
      # though the entire collection.
      bar = ProgressBar.create(:format => '%t |%b>%i| %c/%C %e',
                               :title => "Bootstrapping #{model}",
                               :total => model.count) unless defined?(Promiscuous.testing?)
      model.all.without_promiscuous.each do |instance|
        dep = instance.promiscuous.tracked_dependencies.first
        # TODO Abstract DB operation
        dep.version = instance[Promiscuous::Publisher::Operation::Mongoid::VERSION_FIELD].to_i
        payload = instance.promiscuous.payload
        payload[:operation] = :bootstrap_data
        payload[:dependencies] = {:write => [dep]}
        self.publish(:key => payload[:__amqp__], :payload => MultiJson.dump(payload))
        bar.increment
      end
    end
  end
end
