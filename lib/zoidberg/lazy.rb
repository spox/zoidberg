require 'zoidberg'

module Zoidberg

  # Provide lazy evaluation of an instance for future work
  class Lazy < BasicObject

    # Create a new lazy evaluator
    #
    # @param klass [Class] optional class to use for type checkin
    # @yield block to provide actual instance
    # @return [self]
    def initialize(klass=nil, &block)
      @klass = klass
      unless(block)
        ::Kernel.raise ArgumentError.new('Block is required for providing instance!')
      end
      @instance_block = block
    end

    # Proxy any calls to actual instance
    def method_missing(*args, &block)
      @instance_block.call.send(*args, &block)
    end

    # Customized check to allow for type checking prior to instance
    # being available via lazy loading
    #
    # @param chk [Class]
    # @return [TrueClass, FalseClass]
    def is_a?(chk)
      if(@klass)
        ([@klass] + @klass.ancestors).include?(chk)
      else
        method_missing(:is_a?, chk)
      end
    end

  end

end
