require 'erb'

class Promiscuous::Error::MissingTransaction < Promiscuous::Error::Base
  def initialize
    @controller = Thread.current[:promiscuous_controller]
  end

  def to_s
    ERB.new(<<-ERB.gsub(/^\s+<%/, '<%').gsub(/^ {6}/, ''), nil, '-').result(binding)
      Promiscuous needs to execute all your write queries in a transaction for publishing.
      <% if @controller -%>
      Add this in \e[1m./app/controllers/#{@controller[:controller].controller_path}_controller.rb\e[0m

        class #{@controller[:controller].class}
          \e[1m with_transaction :#{@controller[:action]}\e[0m
        end

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
