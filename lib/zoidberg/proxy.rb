require 'thread'
require 'zoidberg'

module Zoidberg

  class Proxy < BasicObject

    attr_accessor :_build_args
    attr_reader :_locker

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

    def method_missing(*args, &block)
      _aquire_lock!
      res = nil
      begin
        res = @_raw_instance.send(*args, &block)
      rescue ::Zoidberg::Supervise::AbortException => e
        ::Kernel.raise e.original_exception
      rescue ::Exception => e
        if(@_supervised)
          _handle_unexpected_error(e)
        end
        ::Kernel.raise e
      ensure
        _release_lock!
      end
      res
    end

    def _zoidberg_signal=(signal)
      @_zoidberg_signal = signal
    end

    def _zoidberg_signal(sig)
      if(@_zoidberg_signal)
        begin
          @_zoidberg_signal.signal(sig)
        rescue => e
          $stdout.puts "WAT: #{e.class} - #{e}"
        end
      end
    end

    def _zoidberg_locked?
      @_lock.locked?
    end

    def _zoidberg_available?
      !_zoidberg_locked?
    end

    def _aquire_lock!
      @_lock.lock unless @_locker == ::Thread.current
      @_locker = ::Thread.current
      @_locker_count += 1
      _zoidberg_signal(:locked)
    end

    def _release_lock!
      if(@_locker == ::Thread.current)
        @_locker_count -= 1
        if(@_locker_count < 1)
          @_locker = nil
          @_lock.unlock if @_lock.locked?
        end
      end
      _zoidberg_signal(:unlocked)
    end

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
    end

    def _zoidberg_destroy!
      _aquire_lock!
      death_from_above = lambda do
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
    end

    def _zoidberg_object
      self
    end

  end

end
