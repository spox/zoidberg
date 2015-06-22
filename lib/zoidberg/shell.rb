require 'zoidberg'

module Zoidberg
  # Provides a wrapping around a real instance. Including this module
  # within a class will enable magic.
  module Shell

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

      # @return [Zoidberg::Proxy] provide proxy when using `self`
      def self
        @_raw_instance._zoidberg_object
      end

    end

    module ClassMethods

      # Override real instance's .new method to provide a proxy instance
      def new(*args, &block)
        Zoidberg::Proxy.new(self, *args, &block)
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
