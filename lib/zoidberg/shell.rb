require 'zoidberg'

module Zoidberg
  module Shell

    module InstanceMethods

      def _zoidberg_proxy(oxy=nil)
        if(oxy)
          @_zoidberg_proxy = oxy
        end
        @_zoidberg_proxy
      end

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

      def defer
        _zoidberg_proxy._release_lock!
        result = yield
        _zoidberg_proxy._aquire_lock!
        result
      end

      def self
        @_raw_instance._zoidberg_object
      end

    end

    module ClassMethods

      def new(*args, &block)
        Zoidberg::Proxy.new(self, *args, &block)
      end

    end

    def self.included(klass)
      unless(klass.instance_methods.include?(:unshelled_new))
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
