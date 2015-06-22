require 'zoidberg'

module Zoidberg
  class Future

    attr_reader :thread

    def initialize(&block)
      @thread = Thread.new(&block)
    end

    def value
      unless(@value)
        @value = @thread.value
      end
      @value
    end

    def available?
      !thread.alive?
    end

  end
end
