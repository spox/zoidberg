require 'zoidberg'

module Zoidberg

  # Customized exception type used when instance has been terminated
  class DeadException < RuntimeError
  end

  # Provides a wrapping around a real instance. Including this module
  # within a class will enable magic.
  module Shell

    class AsyncProxy
      attr_reader :target
      def initialize(instance)
        @target = instance
      end
      def method_missing(*args, &block)
        Thread.new{ target.send(*args, &block) }
        nil
      end
    end

    module InstanceMethods

      # Provide access to the proxy instance from the real instance
      #
      # @param oxy [Zoidberg::Proxy]
      # @return [NilClass, Zoidberg::Proxy]
      def _zoidberg_proxy(oxy=nil)
        if(oxy)
          @_zoidberg_proxy = oxy
        end
        @_zoidberg_proxy
      end
      alias_method :current_self, :_zoidberg_proxy
      alias_method :current_actor, :_zoidberg_proxy

      # Provide a customized sleep behavior which will unlock the real
      # instance while sleeping
      #
      # @param length [Numeric, NilClass]
      # @return [Float]
      def sleep(length=nil)
        defer do
          start_time = ::Time.now.to_f
          if(length)
            Kernel.sleep(length)
          else
            Kernel.sleep
          end
          ::Time.now.to_f - start_time
        end
      end

      # Unlock current lock on instance and execute given block
      # without locking
      #
      # @yield block to execute without lock
      # @return [Object] result of block
      def defer
        _zoidberg_proxy._release_lock!
        result = yield if block_given?
        _zoidberg_proxy._aquire_lock!
        result
      end

      # Perform an async action
      #
      # @param unlocked [Truthy, Falsey] lock when running
      # @return [AsyncProxy]
      def async(unlocked=false)
        AsyncProxy.new(unlocked ? self : current_self)
      end

      # Link given shelled instance to current shelled instance to
      # handle any exceptions raised from async actions
      #
      # @param inst [Object]
      # @return [TrueClass]
      def link(inst)

      end

    end

    module ClassMethods

      # Override real instance's .new method to provide a proxy instance
      def new(*args, &block)
        proxy = Zoidberg::Proxy.new(self, *args, &block)
        weak_ref = Zoidberg::WeakRef.new(proxy)
        Zoidberg::Proxy.register(weak_ref.__id__, proxy)
        ObjectSpace.define_finalizer(weak_ref, Zoidberg::Proxy.method(:scrub!))
        weak_ref
      end

      def trap_exit(m_name=nil)
        if(m_name)
          @m_name = m_name
        end
        @m_name
      end

    end

    # Inject Shell magic into given class when included
    #
    # @param klass [Class]
    def self.included(klass)
      unless(klass.ancestors.include?(Zoidberg::Shell::InstanceMethods))
        klass.class_eval do

          class << self
            alias_method :unshelled_new, :new
          end

          include InstanceMethods
          extend ClassMethods
        end
      end
    end

  end
end
