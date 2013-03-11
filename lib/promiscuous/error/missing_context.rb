class Promiscuous::Error::MissingContext < Promiscuous::Error::Base
  def message
    require 'erb'
    ERB.new(<<-ERB.gsub(/^\s+<%/, '<%').gsub(/^ {6}/, ''), nil, '-').result(binding)
      Promiscuous needs to execute all your read/write queries in a context for publishing.
      This is what you can do:
       1. Wrap your operations in a Promiscuous context yourself (jobs, etc.):

          Promiscuous::Middleware.with_context 'jobs/name' do
             # Code including all your read and write queries
           end

       2. Disable Promiscuous completely (only for testing):

           RSpec.configure do |config|
             config.around do |example|
               without_promiscuous { example.run }
             end
           end

         Note that opening a context will reactivate promiscuous temporarily
         even if it was disabled.

       3. You are in render() in the Rails controller, and you should not write.
      <% end -%>
    ERB
  end

  alias to_s message
end
