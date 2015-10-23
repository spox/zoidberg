require 'zoidberg'

module Zoidberg

  # Customized exception type used when instance has been terminated
  class DeadException < StandardError
    attr_reader :origin_object_id
    def initialize(message, origin_id=nil)
      super message
      @origin_object_id = origin_id
    end
  end

  # Customized exception type to wrap allowed errors
  class AbortException < StandardError
    attr_accessor :original_exception

    def to_s
      if(original_exception)
        "#{original_exception.class}: #{original_exception}"
      else
        super
      end
    end
  end

  # Librated proxy based shell
  module SoftShell

    class AsyncProxy
      attr_reader :locked
      attr_reader :target
      attr_reader :origin_proxy
      def initialize(locked_async, proxy)
        @locked = locked_async
        @origin_proxy = proxy
        @target = proxy._raw_instance
      end
      def method_missing(*args, &block)
        target._zoidberg_thread(
          Thread.new{
            origin_proxy._aquire_lock! if locked
            got_lock = locked
            begin
              target.send(*args, &block)
            rescue Zoidberg::DeadException => e
              if(e.origin_object_id == target.object_id)
                got_lock = false
              end
              raise
            rescue StandardError, ScriptError => e
              origin_proxy._zoidberg_unexpected_error(e)
              raise
            ensure
              origin_proxy._release_lock! if got_lock
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
      re_lock = _zoidberg_proxy._release_lock!
      begin
        result = yield if block_given?
        result
      rescue ::Zoidberg::DeadException => e
        re_lock = false if e.origin_object_id == object_id
        raise
      rescue ::StandardError, ::ScriptError => e
        raise e
      ensure
        _zoidberg_proxy._aquire_lock! if re_lock
      end
    end

    # Perform an async action
    #
    # @param locked [Truthy, Falsey] lock when running
    # @return [AsyncProxy, NilClass]
    def async(locked=false, &block)
      if(block_given?)
        unless(locked)
          thread = ::Thread.new do
            begin
              self.instance_exec(&block)
            rescue Zoidberg::DeadException => e
              if(e.origin_object_id == object_id)
                raise
              else
                _zoidberg_proxy._zoidberg_unexpected_error(e)
                raise
              end
            rescue ::StandardError, ::ScriptError => e
              _zoidberg_proxy._zoidberg_unexpected_error(e)
              raise
            end
          end
        else
          thread = ::Thread.new do
            _zoidberg_proxy._aquire_lock!
            begin
              got_lock = true
              self.instance_exec(&block)
            rescue Zoidberg::DeadException => e
              if(e.origin_object_id == object_id)
                got_lock = false
              else
                _zoidberg_proxy._zoidberg_unexpected_error(e)
              end
              raise
            rescue ::StandardError, ::ScriptError => e
              _zoidberg_proxy._zoidberg_unexpected_error(e)
              raise
            ensure
              _zoidberg_proxy._release_lock! if got_lock
            end
          end
        end
        _zoidberg_thread(thread)
        nil
      else
        ::Zoidberg::SoftShell::AsyncProxy.new(locked, _zoidberg_proxy)
      end
    end

    # Register a running thread for this instance. Registered
    # threads are tracked and killed on cleanup
    #
    # @param thread [Thread]
    # @return [TrueClass]
    def _zoidberg_thread(thread)
      _zoidberg_proxy._zoidberg_thread(thread)
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
      if(current_self.threaded?)
        action = Task.new(:async, current_self){ block.call }
        current_self.task_defer(action)
        Thread.stop
        action.value
      else
        Fiber.yield
        if(block)
          ::Fiber.new(&block).resume
        end
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
        defer{ ::Kernel.sleep(length) }
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
      def _zoidberg_signal_interface
        _zoidberg_proxy._zoidberg_signal_interface
      end

      # @return [Timer]
      def timer
        _zoidberg_proxy._zoidberg_timer
      end

      # Register a recurring action
      #
      # @param interval [Numeric]
      # @yield action to run
      # @return [Timer]
      def every(interval, &block)
        timer.every(interval, &block)
      end

      # Register an action to run after interval
      #
      # @param interval [Numeric]
      # @yield action to run
      # @return [Timer]
      def after(interval, &block)
        timer.after(interval, &block)
      end

      # Send a signal to single waiter
      #
      # @param name [String, Symbol] name of signal
      # @param arg [Object] optional argument to transmit
      # @return [TrueClass, FalseClass]
      def signal(name, arg=nil)
        _zoidberg_signal_interface.signal(*[name, arg].compact)
      end

      # Broadcast a signal to all waiters
      # @param name [String, Symbol] name of signal
      # @param arg [Object] optional argument to transmit
      # @return [TrueClass, FalseClass]
      def broadcast(name, arg=nil)
        _zoidberg_signal_interface.broadcast(*[name, arg].compact)
      end

      # Wait for a given signal
      #
      # @param name [String, Symbol] name of signal
      # @return [Object]
      def wait_for(name)
        defer{ _zoidberg_signal_interface.wait_for(name) }
      end
      alias_method :wait, :wait_for

      # @return [TrueClass, FalseClass]
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
        if(@_zoidberg_proxy)
          @_zoidberg_proxy
        else
          Lazy.new(self.class){ @_zoidberg_proxy }
        end
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

      # Customized method for raising exceptions that have been
      # properly handled (preventing termination)
      #
      # @param e [Exception]
      # @raises [AbortException]
      def abort(e)
        unless(e.is_a?(::Exception))
          $stdout.puts "E: #{e.class} - #{e.ancestors}"
          e = StandardError.new(e)
        end
        new_e = ::Zoidberg::AbortException.new
        new_e.original_exception = e
        ::Kernel.raise new_e
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
        proxy._zoidberg_set_instance(self.unshelled_new(*args, &block))
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

            # Set an option or multiple options
            #
            # @return [Array<Symbol>]
            def option(*args)
              @option ||= []
              unless(args.empty?)
                @option += args
                @option.map!(&:to_sym).uniq!
              end
              @option
            end

            # Check if option is available
            #
            # @param arg [Symbol]
            # @return [TrueClass, FalseClass]
            def option?(arg)
              option.include?(arg.to_sym)
            end

          end

          include InstanceMethods
          extend ClassMethods
          include Bogo::Memoization
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
