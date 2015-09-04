require 'zoidberg'

module Zoidberg

  # Customized exception type used when instance has been terminated
  class DeadException < RuntimeError; end

  # Librated proxy based shell
  module SoftShell

    class AsyncProxy
      attr_reader :target
      def initialize(instance)
        @target = instance
      end
      def method_missing(*args, &block)
        target._zoidberg_thread(
          Thread.new{
            begin
              target.send(*args, &block)
            rescue Exception => e
              target._zoidberg_proxy.send(:raise, e)
            end
          }
        )
        nil
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
    # @param locked [Truthy, Falsey] lock when running
    # @return [AsyncProxy, NilClass]
    def async(locked=false, &block)
      if(block_given?)
        unless(locked)
          thread = ::Thread.new do
            self.instance_exec(&block)
          end
        else
          thread = ::Thread.new{ current_self.instance_exec(&block) }
        end
        _zoidberg_thread(thread)
        nil
      else
        ::Zoidberg::SoftShell::AsyncProxy.new(locked ? current_self : self)
      end
    end

    # Register a running thread for this instance. Registered
    # threads are tracked and killed on cleanup
    #
    # @param thread [Thread]
    # @return [TrueClass]
    def _zoidberg_thread(thread)
      _zoidberg_proxy._raw_threads[self.object_id].push(thread)
      true
    end

    # Provide a customized sleep behavior which will unlock the real
    # instance while sleeping
    #
    # @param length [Numeric, NilClass]
    # @return [Float]
    def sleep(length=nil)
      if(_zoidberg_proxy._locker == ::Thread.current)
        defer do
          start_time = ::Time.now.to_f
          if(length)
            ::Kernel.sleep(length)
          else
            ::Kernel.sleep
          end
          ::Time.now.to_f - start_time
        end
      else
        start_time = ::Time.now.to_f
        if(length)
          ::Kernel.sleep(length)
        else
          ::Kernel.sleep
        end
        ::Time.now.to_f - start_time
      end
    end

    def self.included(klass)
      unless(klass.include?(::Zoidberg::Shell))
        klass.class_eval do
          include ::Zoidberg::Shell
        end
      end
    end

  end

  # Confined proxy based shell
  module HardShell

    class AsyncProxy
      attr_reader :target, :locked
      def initialize(instance, locked)
        @target = instance
        @locked = locked
      end
      def method_missing(*args, &block)
        target._async_request(locked ? :blocking : :nonblocking, *args, &block)
        nil
      end
    end

    # Unlock current lock on instance and execute given block
    # without locking
    #
    # @yield block to execute without lock
    # @return [Object] result of block
    def defer(&block)
      Fiber.yield
      if(block)
        ::Fiber.new(&block).resume
      end
    end

    # Perform an async action
    #
    # @param locked [Truthy, Falsey] lock when running
    # @return [AsyncProxy, NilClass]
    def async(locked=false, &block)
      if(block)
        if(locked)
          current_self.instance_exec(&block)
        else
          current_self._async_request(locked ? :blocking : :nonblocking, :instance_exec, &block)
        end
      else
        ::Zoidberg::HardShell::AsyncProxy.new(current_self, locked)
      end
    end

    # Provide a customized sleep behavior which will unlock the real
    # instance while sleeping
    #
    # @param length [Numeric, NilClass]
    # @return [Float]
    def sleep(length=nil)
      start_time = ::Time.now.to_f
      if(length)
        ::Kernel.sleep(length)
      else
        ::Thread.current[:root_fiber] == ::Fiber.current ? ::Kernel.sleep : ::Fiber.yield
      end
      ::Time.now.to_f - start_time
    end

    def self.included(klass)
      unless(klass.include?(::Zoidberg::Shell))
        klass.class_eval do
          include ::Zoidberg::Shell
        end
      end
    end

  end

  # Provides a wrapping around a real instance. Including this module
  # within a class will enable magic.
  module Shell

    module InstanceMethods

      # Initialize the signal instance if not
      def _zoidberg_signal_setup
        unless(@_zoidberg_signal)
          _zoidberg_proxy._aquire_lock!
          @_instance_signal ||= ::Zoidberg::Signal.new
          _zoidberg_proxy._release_lock!
        end
      end

      def signal(name, arg=nil)
        _zoidberg_signal_setup
        if(arg)
          @_instance_signal.signal(name, arg)
        else
          @_instance_signal.signal(name)
        end
      end

      def broadcast(name, arg=nil)
        _zoidberg_signal_setup
        if(arg)
          @_instance_signal.broadcast(name, arg)
        else
          @_instance_signal.broadcast(name)
        end
      end

      def wait_for(name)
        _zoidberg_signal_setup
        defer{ @_instance_signal.wait_for(name) }
      end
      alias_method :wait, :wait_for

      def alive?
        !respond_to?(:_zoidberg_destroyed)
      end

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

      # Link given shelled instance to current shelled instance to
      # handle any exceptions raised from async actions
      #
      # @param inst [Object]
      # @return [TrueClass]
      def link(inst)
        inst._zoidberg_link = current_self
        true
      end

    end

    module ClassMethods

      # Override real instance's .new method to provide a proxy instance
      def new(*args, &block)
        if(self.include?(Zoidberg::HardShell))
          proxy = Zoidberg::Proxy::Confined.new(self, *args, &block)
        elsif(self.include?(Zoidberg::SoftShell))
          proxy = Zoidberg::Proxy::Liberated.new(self, *args, &block)
        else
          raise TypeError.new "Unable to determine `Shell` type for this class `#{self}`!"
        end
        weak_ref = Zoidberg::WeakRef.new(proxy)
        Zoidberg::Proxy.register(weak_ref.__id__, proxy)
        ObjectSpace.define_finalizer(weak_ref, Zoidberg::Proxy.method(:scrub!))
        weak_ref
      end

      # Trap unhandled exceptions from linked instances and handle via
      # given method name
      #
      # @param m_name [String, Symbol] method handler name
      # @return [String, Symbol]
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
      unless(klass.include?(SoftShell) || klass.include?(HardShell))
        klass.class_eval do
          include Zoidberg.default_shell
        end
      end
    end

  end
end
