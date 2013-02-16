require 'erb'

module Promiscuous::Publisher::MockGenerator
  def self.generate
    ERB.new(<<-ERB.gsub(/^\s+<%/, '<%').gsub(/^ {6}/, ''), nil, '-').result(binding)
      # ---------------------------------
      # Auto-generated file. Do not edit.
      # ---------------------------------

      module <%= Promiscuous::Config.app.camelize %>::Publishers
      <% modules.each do |mod| -%>
        <%- if mod.constantize.is_a?(Class) -%>
        class <%= mod %>; end
        <%- else -%>
        module <%= mod %>; end
        <% end -%>
      <% end -%>

      <% Promiscuous::Publisher::Model.publishers.each do |publisher| -%>
        <% next unless publisher.publish_to -%>
        <% %>
        # ------------------------------------------------------------------

        class <%= publisher.publish_as %>
          include Promiscuous::Publisher::Model::Mock
          publish :to => '<%= publisher.publish_to %>'
          <% if defined?(Mongoid::Document) && publisher.include?(Mongoid::Document) -%>
          mock    :id => :bson
          <% end -%>
          <% %>
          <% attributes_for(publisher).each do |attr| -%>
          publish :<%= attr %>
          <% end -%>
        end

        <% publisher.descendants.each do |subclass| -%>
        class <%= subclass.publish_as %> < <%= publisher.publish_as %>
          <% attributes_for(subclass, publisher).each do |attr| -%>
          publish :<%= attr %>
          <% end -%>
        end
        <% end -%>
      <% end -%>
      end
    ERB
  end

  def self.attributes_for(klass, parent=nil)
    attrs = klass.published_attrs
    attrs -= parent.published_attrs if parent
    attrs
  end

  def self.modules
    Promiscuous::Publisher::Model.publishers
      .map    { |publisher| [publisher] + publisher.descendants.map(&:name) }
      .flatten
      .select { |name| name =~ /::/ }
      .map    { |name| name.gsub(/::[^:]+$/, '') }
      .uniq
      .sort
  end
end
