require 'zoidberg'

module Zoidberg
  class Supervisor

    include Zoidberg::Shell

    # @return [Registry] current supervision registry
    attr_reader :registry

    # Create a new supervisor
    #
    # @return [self]
    def initialize
      @registry = Registry.new
    end

    # Fetch the supervised instance or pool
    #
    # @param k [String, Symbol] name of supervised item
    # @return [Object] supervised object
    def [](k)
      registry[k]
    end

    # Supervise an instance
    #
    # @param name [String, Symbol] name of item to supervise
    # @param klass [Class] class of instance
    # @param args [Object] initialization arguments
    # @yieldblock initialization block
    # @return [Object] new instance
    def supervise_as(name, klass, *args, &block)
      klass = supervised_class(klass)
      registry[name] = klass.new(*args, &block)
    end

    # Supervise a pool
    #
    # @param klass [Class] class of instance
    # @param args [Hash] initialization arguments
    # @option args [String] :as name of pool
    # @option args [Integer] :size size of pool
    # @option args [Array<Object>] :args initialization arguments
    # @yieldblock initialization block
    # @return [Object] new pool
    def pool(klass, args={}, &block)
      name = args[:as]
      size = args[:size].to_i
      args = args.fetch(:args, [])
      klass = supervised_class(klass)
      s_pool = Pool.new(klass, *args, &block)
      s_pool._worker_count(size > 0 ? size : 1)
      registry[name] = s_pool
    end

    protected

    # Make a supervised class
    #
    # @param klass [Class]
    # @return [Class]
    def supervised_class(klass)
      unless(klass.include?(Zoidberg::Supervise))
        n_klass = Class.new(klass) do
          include Zoidberg::Supervise
        end
        n_klass.class_eval("def self.name; '#{klass.name}'; end")
        klass = n_klass
      end
      klass
    end

  end
end
