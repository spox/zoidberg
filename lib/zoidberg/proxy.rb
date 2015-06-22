require 'thread'
require 'zoidberg'

module Zoidberg

  # Instance proxy that filters requests to shelled instance
  class Proxy < BasicObject

    # @return [Array] arguments used to build real instance
    attr_accessor :_build_args
    # @return [Thread] current owner of lock
    attr_reader :_locker

    # Create a new proxy instance, new real instance, and link them
    #
    # @return [self]
    def initialize(klass, *args, &block)
      @_build_args = [klass, args, block]
      @_raw_instance = klass.unshelled_new(*args, &block)
      @_raw_instance._zoidberg_proxy(self)
      @_lock = ::Mutex.new
      @_count_lock = ::Mutex.new
      @_locker = nil
      @_locker_count = 0
      @_zoidberg_signal = nil
      if(@_raw_instance.class.ancestors.include?(::Zoidberg::Supervise))
        @_supervised = true
      end
    end

    # Used to proxy request to real instance
    def method_missing(*args, &block)
      begin
        _aquire_lock!
        res = nil
        res = @_raw_instance.send(*args, &block)
      rescue ::Zoidberg::Supervise::AbortException => e
        ::Kernel.raise e.original_exception
      rescue ::Exception => e
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
        begin
          @_zoidberg_signal.signal(sig)
          true
        rescue => e
          $stdout.puts "WAT: #{e.class} - #{e}"
        end
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
      death_from_above = ::Proc.new do
        ::Kernel.raise ::Zoidberg::Supervise::DeadException.new('Instance in terminated state!')
      end
      m_scrub = (
        @_raw_instance.public_methods +
        @_raw_instance.protected_methods
      ) - ::Object.public_instance_methods
      m_scrub.each do |m_name|
        next if [:object_id, :defined_singleton_method, :send].include?(m_name)
        @_raw_instance.send(:define_singleton_method, m_name, &death_from_above)
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
