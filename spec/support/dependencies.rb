module DependencyHelper
  class Proxy
    def [](*strs)
      strs.map { |s| Promiscuous::Dependency.parse(s).to_s }
    end
  end

  def hashed
    Proxy.new
  end
end
