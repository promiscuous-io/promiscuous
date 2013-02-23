class Promiscuous::Error::MissingTransaction < Promiscuous::Error::Base
  def to_s
    "Promiscuous needs to execute all your queries (read and write) in a transaction.\n" +
    "This is what you can do:\n" +
    "  - Wrap your operations in a Promiscuous transaction:\n\n" +
    "      Promiscuous.transaction(\"some_name\") do\n" +
    "        # Code including all your read and write queries\n" +
    "      end\n\n" +
    "    Note:\n" +
    "      * The transaction name is used to learn which transactions contains write queries.\n" +
    "      * Rails controllers are wrapped by Promiscuous automatically with a unique naming convention.\n\n" +
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
    "    Note that if you hit your controllers, Promiscuous will activate due to the presence of a transaction."
  end
end
