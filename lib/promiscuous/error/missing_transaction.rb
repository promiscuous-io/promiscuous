require 'erb'

class Promiscuous::Error::MissingTransaction < Promiscuous::Error::Base
  def initialize
    @controller = Thread.current[:promiscuous_controller]
    be_smart if ENV['BE_SMART'] && @controller
  end

  def be_smart
    file = Rails.root.join(full_path)
    File.open(file, File::RDWR) do |f|
      # for parallel testing
      f.flock(File::LOCK_EX)

      lines = f.read.split("\n")
      lines.each do |line|
        if line =~ /^\s*with_transaction :.*/
          # append atomically
          line << ", :#{@controller[:action]}" unless line =~ /:#{@controller[:action]}(,| |$)/
          @fixed_it = true
          break
        end
      end

      if !@fixed_it
        lines.each_with_index do |line, i|
          if line =~ /^(\s*)class.*#{@controller[:controller].class.name.split('::').last} /
            # add
            lines.insert(i+1, "#{$1}  with_transaction :#{@controller[:action]}")
            lines.insert(i+2, "") if lines[i+2] =~ /^\s*def\b/
            @fixed_it = true
            break
          end
        end
      end

      if @fixed_it
        f.rewind
        f.write(lines.join("\n")+"\n")
        f.truncate(f.pos)
      end
    end

    load file if @fixed_it
  end

  def full_path
    "./app/controllers/#{@controller[:controller].controller_path}_controller.rb"
  end

  def to_s
    ERB.new(<<-ERB.gsub(/^\s+<%/, '<%').gsub(/^ {6}/, ''), nil, '-').result(binding)
      Promiscuous needs to execute all your write queries in a transaction for publishing.
      <% if @controller -%>
        <% if @fixed_it -%>

      \e[0;32mPromiscuous edited and reloaded \e[1m<%= full_path %>\e[0;32m to add this:
        <% else -%>
      Add this in \e[1m<%= full_path %>\e[0m
        <% end -%>

        class <%= @controller[:controller].class %>
          \e[1m with_transaction :<%= @controller[:action] %>\e[0m
        end

        Protip: Run your test with BE_SMART=1 and Promiscuous will edit your files for you.
                It supports parallel testing.

      <% else -%>
      This is what you can do:
       1. Wrap your operations in a Promiscuous transaction yourself (jobs, etc.):

           Promiscuous.transaction do
             # Code including all your read and write queries
           end

       2. Disable Promiscuous transactions (dangerous):
           Promiscuous::Config.use_transactions = false
           # Code including all your read and write queries

         The Rails console runs in this mode in development mode.

       3. Disable Promiscuous completely (only for testing):

           RSpec.configure do |config|
             config.around do |example|
               without_promiscuous { example.run }
             end
           end

         Note that opening a transaction will reactivate promiscuous during the transaction.
      <% end -%>
    ERB
  end
end
