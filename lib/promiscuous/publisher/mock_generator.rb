class Promiscuous::Publisher::MockGenerator
  def initialize(output)
    @out = SourceOutput.new(output)
  end

  def generate
    @out << "module #{Promiscuous::Config.app.camelize}::Publishers"
    @out.indent
    @out << "# Auto-generated file"

    Promiscuous::Publisher::Model.publishers.map do |publisher|
      next unless publisher.publish_to

      publisher_for(publisher) do
        @out << "include Promiscuous::Publisher::Model::Mock"
        @out << "publish :to => '#{publisher.publish_to}'"
        attributes_for(publisher)
      end

      publisher.descendants.each do |subclass|
        publisher_for(subclass, publisher) do
          attributes_for(subclass, publisher)
        end
      end

    end
    @out.outdent
    @out << "end"

    true
  end

  def publisher_for(klass, parent=nil, &block)
    @out << '' unless parent
    @out << (parent ? "class #{klass} < #{parent}" : "class #{klass}")
    @out.indent
    yield
    @out.outdent
    @out << 'end'
  end

  def attributes_for(klass, parent=nil)
    attrs = klass.published_attrs
    attrs -= parent.published_attrs if parent
    attrs.each do |attr|
      @out << "publish :#{attr}"
    end
  end

  class SourceOutput
    attr_accessor :output
    def initialize(output)
      self.output = output.nil? ? STDOUT : output
      @level = 0
    end

    def indent
      @level += 2
    end

    def outdent
      @level -= 2
    end

    def <<(string)
      output << (string.present? ? (" " * @level) + string : string) + "\n"
    end
  end
end
