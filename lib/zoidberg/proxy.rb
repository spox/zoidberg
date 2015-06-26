require 'zoidberg'

module Zoidberg

  # Instance proxy that filters requests to shelled instance
  class Proxy < BasicObject

    @@__registry = ::Hash.new

    class << self

      # @return [Hash] WeakRef -> Proxy mapping
      def registry
        @@__registry
      end

      # Register the proxy a WeakRef is pointing to
      #
      # @param r_id [Integer] object ID of WeakRef
      # @param proxy [Zoidberg::Proxy] actual proxy instance
      # @return [Zoidberg::Proxy]
      def register(r_id, proxy)
        @@__registry[r_id] = proxy
      end

      # Destroy the proxy referenced by the WeakRef with the provided
      # ID
      #
      # @param o_id [Integer] Object ID
      # @return [Truthy, Falsey]
      def scrub!(o_id)
        proxy = @@__registry.delete(o_id)
        if(proxy)
          proxy._zoidberg_destroy!
        end
      end

    end

    # @return [Array] arguments used to build real instance
    attr_accessor :_build_args
    # @return [Thread] current owner of lock
    attr_reader :_locker
    # @return [Object] wrapped instance
    attr_reader :_raw_instance
    # @return [Hash<Integer:Thread>]
    attr_reader :_raw_threads

    # Create a new proxy instance, new real instance, and link them
    #
    # @return [self]
    def initialize(klass, *args, &block)
      @_build_args = [klass, args, block]
      @_raw_instance = klass.unshelled_new(*args, &block)
      @_lock = ::Mutex.new
      @_count_lock = ::Mutex.new
      @_locker = nil
      @_locker_count = 0
      @_zoidberg_signal = nil
      @_raw_instance._zoidberg_proxy(self)
      @_raw_threads = ::Smash.new{ ::Array.new }
      if(@_raw_instance.class.ancestors.include?(::Zoidberg::Supervise))
        @_supervised = true
      end
    end

    # Used to proxy request to real instance
    def method_missing(*args, &block)
      begin
        _aquire_lock!
        res = nil
        if(::ENV['ZOIDBERG_TESTING'])
          ::Kernel.require 'timeout'
          ::Timeout.timeout(20) do
            res = @_raw_instance.__send__(*args, &block)
          end
        else
          res = @_raw_instance.__send__(*args, &block)
        end
      rescue ::Zoidberg::Supervise::AbortException => e
        ::Kernel.raise e.original_exception
      rescue ::Exception => e
        if(defined?(Timeout) && e.is_a?(Timeout::Error))
          ::Kernel.raise e
        end
        if(_zoidberg_link)
          if(_zoidberg_link.class.trap_exit)
            _zoidberg_link.async.send(
              _zoidberg_link.class.trap_exit, @_raw_instance, e
            )
          end
        end
        if(@_supervised)
          _handle_unexpected_error(e)
        end
        if(e.class.to_s == 'fatal' && !@_fatal_retry)
          @_fatal_retry = true
          retry
        else
          ::Kernel.raise e
        end
      ensure
        _release_lock!
      end
      res
    end

    # @return [Object]
    def _zoidberg_link=(inst)
      @_zoidberg_link = inst
    end

    # @return [Object, NilClass]
    def _zoidberg_link
      @_zoidberg_link
    end

    # Set an optional state signal instance
    #
    # @param signal [Signal]
    # @return [Signal]
    def _zoidberg_signal=(signal)
      @_zoidberg_signal = signal
    end

    # Send a signal if the optional signal instance has been set
    #
    # @param sig [Symbol]
    # @return [TrueClass, FalseClass] signal was sent
    def _zoidberg_signal(sig)
      if(@_zoidberg_signal)
        @_zoidberg_signal.signal(sig)
        true
      else
        false
      end
    end

    # @return [TrueClass, FalseClass] currently locked
    def _zoidberg_locked?
      @_lock.locked?
    end

    # @return [TrueClass, FalseClass] currently unlocked
    def _zoidberg_available?
      !_zoidberg_locked?
    end

    # Aquire the lock to access real instance. If already locked, will
    # wait until lock can be aquired.
    #
    # @return [TrueClas]
    def _aquire_lock!
      @_lock.lock unless @_locker == ::Thread.current
      @_locker = ::Thread.current
      @_locker_count += 1
      _zoidberg_signal(:locked)
      true
    end

    # Release the lock to access real instance
    #
    # @return [TrueClass]
    def _release_lock!
      if(@_locker == ::Thread.current)
        @_locker_count -= 1
        if(@_locker_count < 1)
          @_locker = nil
          @_lock.unlock if @_lock.locked?
        end
      end
      _zoidberg_signal(:unlocked)
      true
    end

    # When real instance is being supervised, unexpected exceptions
    # will force the real instance to be terminated and replaced with
    # a fresh instance. If the real instance provides a #restart
    # method that will be called instead of forcibly terminating the
    # current real instance and rebuild a new instance.
    #
    # @param error [Exception] exception that was caught
    # @return [TrueClass]
    def _handle_unexpected_error(error)
      if(@_raw_instance.respond_to?(:restart))
        @_raw_instance.restart(error)
      else
        if(@_raw_instance.respond_to?(:terminate))
          @_raw_instance.terminate
        end
        _zoidberg_destroy!
        args = _build_args.dup
        @_raw_instance = args.shift.unshelled_new(
          *args.first,
          &args.last
        )
        @_raw_instance._zoidberg_proxy(self)
      end
      true
    end

    # Destroy the real instance. Will update all methods on real
    # instance to raise exceptions noting it as terminated rendering
    # it unusable. This is generally used with the supervise module
    # but can be used on its own if desired.
    #
    # @return [TrueClass]
    def _zoidberg_destroy!
      _aquire_lock!
      unless(@_raw_instance.respond_to?(:_zoidberg_destroyed))
        death_from_above = ::Proc.new do
          ::Kernel.raise ::Zoidberg::DeadException.new('Instance in terminated state!')
        end
        death_from_above_display = ::Proc.new do
          "#<#{self.class}:TERMINATED>"
        end
        (
          @_raw_instance.public_methods(false) +
          @_raw_instance.protected_methods(false) +
          @_raw_instance.private_methods(false)
        ).each do |m_name|
          @_raw_instance.send(:define_singleton_method, m_name, &death_from_above)
        end
        @_raw_instance.send(:define_singleton_method, :to_s, &death_from_above_display)
        @_raw_instance.send(:define_singleton_method, :inspect, &death_from_above_display)
        @_raw_threads[@_raw_instance.object_id].map do |thread|
          thread.raise ::Zoidberg::DeadException.new('Instance in terminated state!')
        end.map do |thread|
          thread.join(2)
        end.find_all(&:alive?).map(&:kill)
        @_raw_threads.delete(@_raw_instance.object_id)
        @_raw_instance.send(:define_singleton_method, :_zoidberg_destroyed, ::Proc.new{ true })
      end
      _zoidberg_signal(:destroyed)
      _release_lock!
      true
    end

    # @return [self]
    def _zoidberg_object
      self
    end

  end

end

# jruby compat [https://github.com/jruby/jruby/pull/2520]
if(Zoidberg::Proxy.instance_methods.include?(:object_id))
  class Zoidberg::Proxy
    undef_method :object_id
  end
end
