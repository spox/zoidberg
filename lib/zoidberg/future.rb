require 'zoidberg'

module Zoidberg
  # Perform action and fetch result in the future
  class Future

    # @return [Concurrent::Future] underlying thread running task
    attr_reader :future

    # Create a new instance
    #
    # @yield block to execute
    # @return [self]
    def initialize(&block)
      @future = Concurrent::Future.execute(&block)
    end

    # @return [Object] result value
    def value
      unless(@value)
        @value = @future.value
      end
      @value
    end

    # Check if value is available
    #
    # @return [TrueClass, FalseClass]
    def available?
      future.fulfilled?
    end

  end
end
