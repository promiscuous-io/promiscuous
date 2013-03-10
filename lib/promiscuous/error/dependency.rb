class Promiscuous::Error::Dependency < Promiscuous::Error::Base
  attr_accessor :dependency_solutions, :operation, :context

  def initialize(options={})
    self.dependency_solutions = options[:dependency_solutions]
    self.operation = options[:operation]
    self.context = Promiscuous::Publisher::Context.current
  end

  # TODO Convert all that with Erb

  def message
    msg = nil
    case operation.operation
    when :read
      msg =  "Promiscuous doesn't have any tracked dependencies to perform this multi read operation.\n" +
             "This is what you can do:\n\n" +
             "  1. Bypass Promiscuous\n\n" +
             "     If you don't use the result of this operation in your following writes,\n" +
             "     you can wrap your read query in a 'without_promiscuous { }' block.\n" +
             "     This is the preferred solution when you are sure that the read doesn't\n" +
             "     influence the value of a published attribute.\n\n" +
             "     Rule of thumb: Predicates (methods ending with ?) are often suitable for this use case.\n\n" +
             "  2. Use a Nested context\n\n" +
             "     Nested contexts can be used to optimize performance by identifying\n"+
             "     blocks of code that do not depend on each other. A typical pattern is the\n"+
             "     'last_visited_at' update in a before filter of all controllers.\n\n"
      cnt = 3
      if operation.operation_ext != :count
        msg += "  #{cnt}. Synchronize on individual instances\n\n" +
               "     If the collection you are iterating through is small (<10), it becomes intersting\n" +
               "     to track instances through their ids instead of the query selector. Example:\n\n" +
               "          criteria.without_promiscuous.each do |doc|\n" +
               "            next if doc.should_do_something?\n" +
               "            doc.reload # tell promiscuous to track the instance\n" +
               "            doc.do_something!\n" +
               "          end\n\n" +
        cnt += 1
      end
      if dependency_solutions.present?
        msg += "  #{cnt}. Track New Dependencies\n\n" +
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

    msg += "Promiscuous cannot allow the following "
    case operation.operation_ext || operation.operation
    when :count     then msg += 'count'
    when :mapreduce then msg += 'mapreduce'
    when :read      then msg += 'each loop'
    when :update    then msg += 'multi update'
    when :destroy   then msg += 'multi destroy'
    end
    msg += " in the '#{context.name}' context:\n\n"
    msg += "  #{self.class.explain_operation(self.operation)}"
    msg += "\n\nProTip: Try again with TRACE=2 in the shell or ENV['TRACE']='2' in the console.\n" unless ENV['TRACE']
    msg
  rescue Exception => e
    "#{e.to_s}\n#{e.backtrace.join("\n")}"
  end

  def self.explain_operation(operation, limit=100)
    instance = operation.instance
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
      msg
    end
  end

  def self.get_selector(attributes, limit=100)
    attributes = attributes['$set'] if attributes.count == 1 && attributes['$set']
    selector = attributes.map { |k,v| ":#{k} => #{v}" }.join(", ")
    selector = "#{selector[0...(limit-3)]}..." if selector.size > limit
    selector
  end

  alias to_s message
end
