class Promiscuous::Error::Dependency < RuntimeError
  attr_accessor :dependency_solutions, :query, :operation

  def initialize(options={})
    self.dependency_solutions = options[:dependency_solutions]
    self.query     = options[:query]
    self.operation = options[:operation]
  end

  def message
    msg = nil
    case operation
    when :read
      msg = "Promiscuous doesn't have any tracked dependencies to perform this multi read operation.\n" +
            "This is what you can do:\n" +
            "  - If you don't use the result of this operation in your following writes,\n" +
            "    you can wrap your read query in a 'without_promiscuous { }' block\n" +
            "  - Read each of the documents one by one"
      if dependency_solutions.present?
        msg += "\n"+
               "  - Add a new dependency to track (which slows down your writes).\n" +
               "    You should use the most specific field (least amount of matching documents for a given value).\n" +
               "    Add one of the following line in your model to resolve your issue:\n"
                    dependency_solutions.map { |field| "         track_dependencies_of :#{field}" }.join("\n")
      end
    when :create
      # no dependency problem
    when :update
      msg = "Promiscuous cannot track dependencies of a multi update operation.\n" +
             "This is what you can do:\n" +
             "  - Instead of doing a multi updates, update each instance separately\n" +
             "  - Do not assign has_many associations directly, but use the << operator instead."
    when :destroy
      msg = "Promiscuous cannot track dependencies of a multi delete operation.\n" +
             "This is what you can do:\n" +
            "   - Instead of doing a multi delete, delete each instance separatly.\n" +
            "   - Use destroy_all instead of destroy_all.\n" +
            "   - Declare your has_many relationships with :dependent => :destroy instead of :delete."
    end

    msg + "\n\nThe offending query is: #{query}.\n " if query
    msg
  end

  def to_s
    message
  end
end
