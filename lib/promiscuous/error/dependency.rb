class Promiscuous::Error::Dependency < RuntimeError
  attr_accessor :dependency_solutions, :operation, :transaction

  def initialize(options={})
    self.dependency_solutions = options[:dependency_solutions]
    self.operation = options[:operation]
    self.transaction = Promiscuous::Publisher::Transaction.current
  end

  def message
    msg = nil
    case operation.operation
    when :read
      msg = "Promiscuous doesn't have any tracked dependencies to perform this multi read operation.\n" +
            "This is what you can do:\n\n" +
            "  - If you don't use the result of this operation in your following writes,\n" +
            "    you can wrap your read query in a 'without_promiscuous { }' block.\n\n" +
            "  - Read each of the documents one by one (not implemented yet, it's a bad idea anyway).\n\n" +
            "  - Wrap earlier writes in a transaction if they are seldom. Example:\n\n" +
            "      class Member\n" +
            "        def update_last_visited_at\n" +
            "          Promiscuous.transaction(:update_last_visited_at) do\n" +
            "            update_attributes(:last_visited_at => Time.now)\n" +
            "          end\n" +
            "        end\n" +
            "      end\n\n"
      if dependency_solutions.present?
        msg += "  - Add a new dependency to track by adding #{dependency_solutions.count == 1 ?
                    "the following line" : "one of the following lines"} in the #{operation.instance.class} model:\n\n" +
               "      class #{operation.instance.class}\n" +
                    dependency_solutions.map { |field| "         track_dependencies_of :#{field}" }.join("\n") + "\n" +
               "      end\n\n" +
               (dependency_solutions.count > 1 ?
               "    You should use the most specific field (least amount of matching documents for a given value).\n" +
               "    Tracking 'user_id' is almost always a safe choice for example.\n\n" : "") +
               "    Note that this tracking slow your writes (tracking is the analogous of an index on a regular database)\n" +
               "    You may find more information on the implications on the Promiscuous wiki (TODO:link).\n\n"
      end
    when :update
      msg = "Promiscuous cannot track dependencies of a multi update operation.\n" +
             "This is what you can do:\n\n" +
             "  - Instead of doing a multi updates, update each instance separately\n\n" +
             "  - Do not assign has_many associations directly, but use the << operator instead.\n\n"
    when :destroy
      msg = "Promiscuous cannot track dependencies of a multi delete operation.\n" +
             "This is what you can do:\n\n" +
            "   - Instead of doing a multi delete, delete each instance separatly.\n\n" +
            "   - Use destroy_all instead of destroy_all.\n\n" +
            "   - Declare your has_many relationships with :dependent => :destroy instead of :delete.\n\n"
    end

    if operation.operation == :read
      if transaction.commited_writes.present?
        msg += "Promiscuous is tracking this read because of these earlier writes:\n\n"
        msg += transaction.commited_writes.map { |operation| "  #{explain_operation(operation)}" }.join("\n")
      else
        msg += "Promiscuous is tracking this read because this controller (#{transaction.name}) used to write.\n\n"
      end
    end

    msg += "The problem comes from the following "
    case operation.operation_ext || operation.operation
    when :count   then msg += 'count'
    when :read    then msg += 'each loop'
    when :update  then msg += 'multi update'
    when :destroy then msg += 'multi destroy'
    end
    msg += ":\n\n  #{explain_operation(self.operation)}"

    msg
  rescue Exception => e
    "#{e.to_s}\n#{e.backtrace.join("\n")}"
  end

  def explain_operation(operation)
    selector = operation.instance.attributes.map { |k,v| ":#{k} => #{v}" }.join(", ")
    selector = "#{selector[0...(100-3)]}..." if selector.size > 100
    if operation.operation == :create
      "#{operation.instance.class}.create(#{selector})"
    else
      case operation.operation_ext || operation.operation
      when :count   then verb = 'count'
      when :read    then verb = 'each { ... }'
      when :update  then verb = 'update_all'
      when :destroy then verb = 'delete_all'
      end
      "#{operation.instance.class}.where(#{selector}).#{verb}"
    end
  end

  def to_s
    message
  end
end
