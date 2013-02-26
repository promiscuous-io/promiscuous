class Promiscuous::Error::MissingTransaction < Promiscuous::Error::Base
  def to_s
    "Promiscuous needs to execute all your queries (read and write) in a transaction.\n" +
    "This is what you can do:\n\n" +
    "  - For Rails Controllers:\n\n" +
    "      class SomeController\n"+
    "        with_transaction :action\n"+
    "      end\n\n"+
    "  - Wrap your operations in a Promiscuous transaction yourself (jobs, etc.):\n\n" +
    "      Promiscuous.transaction(\"some_name\") do\n" +
    "        # Code including all your read and write queries\n" +
    "      end\n\n" +
    "  - Disable Promiscuous transactions (dangerous):\n\n" +
    "      Promiscuous::Config.use_transactions = false\n" +
    "      # Code including all your read and write queries\n\n" +
    "    The Rails console runs in this mode in development mode.\n\n" +
    "  - Disable Promiscuous completely (only for testing):\n\n" +
    "      RSpec.configure do |config|\n" +
    "        config.around do |example|\n" +
    "          without_promiscuous { example.run }\n" +
    "        end\n" +
    "      end\n\n" +
    "    Note that opening a transaction will reactivate promiscuous during the transaction.\n\n"
  end
end
