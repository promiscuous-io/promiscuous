class Promiscuous::Error::Dependency < Promiscuous::Error::Base
  attr_accessor :dependency_solutions, :operation, :transaction

  def initialize(options={})
    self.dependency_solutions = options[:dependency_solutions]
    self.operation = options[:operation]
    self.transaction = Promiscuous::Publisher::Transaction.current
  end

  # TODO Convert all that with Erb

  def message
    msg = nil
    case operation.operation
    when :read
      msg = "Promiscuous doesn't have any tracked dependencies to perform this multi read operation.\n" +
            "This is what you can do:\n\n" +
            "  1. Bypass Promiscuous\n\n" +
            "     If you don't use the result of this operation in your following writes,\n" +
            "     you can wrap your read query in a 'without_promiscuous { }' block.\n" +
            "     This is the preferred solution when you are sure that the read doesn't\n" +
            "     influence the value of a published attribute.\n\n" +
            "  2. Use a Nested Transaction\n\n" +
            "     a) Nested transaction can be used to optimize performance by identifying\n"+
            "        blocks of code that do not depend on each other. A typical pattern is the\n"+
            "        'last_visited_at' update in a before filter of all controllers\n" +
            "     b) Some earlier writes may have had happen in in this controller.\n"+
            "        Try to identify offening writes (TRACE=2), and reevaluate a).\n\n"+
            "     Promiscuous will adjust its write predictions and dependencies accordingly\n" +
            "     when using transactions.\n" +
            "     Refer to the wiki for details of the black magic (TODO).\n\n"
      if dependency_solutions.present?
        msg += "  3. Track New Dependencies\n\n" +
               "     Add #{dependency_solutions.count == 1 ? "the following line" : "one of the following lines"} " +
                    "in the #{operation.instance.class} model:\n\n" +
               "       class #{operation.instance.class}\n" +
                    dependency_solutions.map { |field| "         track_dependencies_of :#{field}" }.join("\n") + "\n" +
               "       end\n\n" +
               (dependency_solutions.count > 1 ?
               "     The more specific field, the better. Promiscuous works better when working with small subsets\n" +
               "     For example, tracking something like 'member_id' is a fairly safe choice.\n\n" : "") +
               "     Note that dependency tracking slows down your writes. It can be seen as the analogous\n" +
               "     of an index on a regular database.\n" +
               "     You may find more information about the implications in the Promiscuous wiki (TODO:link).\n\n"
      end
    when :update
      msg = "Promiscuous cannot track dependencies of a multi update operation.\n" +
             "This is what you can do:\n\n" +
             "  1. Instead of doing a multi updates, update each instance separately\n\n" +
             "  2. Do not assign has_many associations directly, but use the << operator instead.\n\n"
    when :destroy
      msg = "Promiscuous cannot track dependencies of a multi delete operation.\n" +
             "This is what you can do:\n\n" +
            "   1. Instead of doing a multi delete, delete each instance separatly.\n\n" +
            "   2. Use destroy_all instead of destroy_all.\n\n" +
            "   3. Declare your has_many relationships with :dependent => :destroy instead of :delete.\n\n"
    end

    msg += "#{"-" * 100}\n\n"

    msg += explain_transaction(transaction)

    msg += "The problem comes from the following "
    case operation.operation_ext || operation.operation
    when :count     then msg += 'count'
    when :mapreduce then msg += 'mapreduce'
    when :read      then msg += 'each loop'
    when :update    then msg += 'multi update'
    when :destroy   then msg += 'multi destroy'
    end
    msg += ":\n\n  #{self.class.explain_operation(self.operation)}"
    msg += "\n\nProTip: Try again with TRACE=1 in the shell or ENV['TRACE']='1' in the console.\n" unless ENV['TRACE']
    msg += "You may use TRACE=N to print N-1 lines of backtraces for each operation."  unless ENV['TRACE']
    msg
  rescue Exception => e
    "#{e.to_s}\n#{e.backtrace.join("\n")}"
  end

  def explain_transaction(transaction)
    msg = ""
    if operation.operation == :read
      t = nil
      if transaction.write_attempts.present?
        msg += "Promiscuous is tracking this read because of these earlier writes:\n\n"
        t = transaction
      else
        transaction.class.with_earlier_transaction(transaction.name) { |_t| t = _t }
        return "" unless t
        call_distance = Promiscuous::Config.transaction_forget_rate - t[:counter]
        t = t[:transaction]
        msg += "Promiscuous is tracking this read because this controller (#{transaction.name}) used to write.\n" +
               "#{call_distance == 1 ? 'One call' : "#{call_distance} calls"} back, this controller wrote:\n\n"
      end
      msg += t.write_attempts.map { |operation| "  #{self.class.explain_operation(operation)}" }.join("\n") + "\n\n"
    end
    msg
  end

  def self.explain_operation(operation, limit=100)
    instance = operation.old_instance || operation.instance
    selector   = instance ? get_selector(instance.attributes, limit) : ""
    class_name = instance ? instance.class : "Unknown"

    if operation.operation == :create
      "#{instance.class}.create(#{selector})"
    else
      case operation.operation_ext || operation.operation
      when :count     then verb = 'count'
      when :mapreduce then verb = 'mapreduce(...)'
      when :read      then verb = operation.multi? ? 'each { ... }' : 'first'
      when :update    then verb = operation.multi? ? 'update_all'   : 'update'
      when :destroy   then verb = operation.multi? ? 'delete_all'   : 'delete'
      end
      msg = "#{class_name}#{selector.present? ? ".where(#{selector})" : ""}.#{verb}"
      if operation.operation == :update && operation.respond_to?(:change) && operation.change
        msg += "(#{get_selector(operation.change, limit)})"
      end
      msg += " (missed)" if operation.missed?
      msg
    end
  end

  def self.get_selector(attributes, limit=100)
    attributes = attributes['$set'] if attributes.count == 1 && attributes['$set']
    selector = attributes.map { |k,v| ":#{k} => #{v}" }.join(", ")
    selector = "#{selector[0...(limit-3)]}..." if selector.size > limit
    selector
  end

  def to_s
    message
  end
end
