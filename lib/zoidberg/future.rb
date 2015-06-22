require 'zoidberg'

module Zoidberg
  # Perform action and fetch result in the future
  class Future

    # @return [Thread] underlying thread running task
    attr_reader :thread

    # Create a new instance
    #
    # @yield block to execute
    # @return [self]
    def initialize(&block)
      @thread = Thread.new(&block)
    end

    # @return [Object] result value
    def value
      unless(@value)
        @value = @thread.value
      end
      @value
    end

    # Check if value is available
    #
    # @return [TrueClass, FalseClass]
    def available?
      !thread.alive?
    end

  end
end
