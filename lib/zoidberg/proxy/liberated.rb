require 'zoidberg'

module Zoidberg
  class Proxy

    class Liberated < Proxy

      # @return [Thread] current owner of lock
      attr_reader :_locker
      # @return [Hash<Integer:Thread>]
      attr_reader :_raw_threads

      # Create a new proxy instance, new real instance, and link them
      #
      # @return [self]
      def initialize(klass, *args, &block)
        @_build_args = [klass, args, block]
        @_lock = ::Mutex.new
        @_count_lock = ::Mutex.new
        @_accessing_threads = []
        @_locker = nil
        @_locker_count = 0
        @_zoidberg_signal = nil
        @_raw_instance = klass.unshelled_new(*args, &block)
        @_raw_instance._zoidberg_proxy(self)
        @_raw_threads = ::Smash.new{ ::Array.new }
        if(@_raw_instance.class.ancestors.include?(::Zoidberg::Supervise))
          @_supervised = true
        end
      end

      # Used to proxy request to real instance
      def method_missing(*args, &block)
        res = nil
        @_accessing_threads << ::Thread.current
        begin
          _aquire_lock!
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
          ::Zoidberg.logger.error "Unexpected exception: #{e.class} - #{e}"
          if((defined?(Timeout) && e.is_a?(Timeout::Error)) || e.is_a?(::Zoidberg::DeadException))
            ::Kernel.raise e
          end
          if(_zoidberg_link)
            if(_zoidberg_link.class.trap_exit)
              ::Zoidberg.logger.warn "Calling linked exit trapper #{@_raw_instance.class} -> #{_zoidberg_link.class}: #{e.class} - #{e}"
              _zoidberg_link.async.send(
                _zoidberg_link.class.trap_exit, @_raw_instance, e
              )
            end
          else
            if(@_supervised)
              ::Zoidberg.logger.warn "Unexpected error for supervised class `#{@_raw_instance.class}`. Handling error (#{e.class} - #{e})"
              _zoidberg_handle_unexpected_error(e)
            end
          end
          if(e.class.to_s == 'fatal' && !@_fatal_retry)
            @_fatal_retry = true
            retry
          else
            ::Kernel.raise e
          end
        ensure
          _release_lock!
          t_idx = @_accessing_threads.index(::Thread.current)
          @_accessing_threads.delete_at(t_idx) if t_idx
        end
        res
      end

      # @return [TrueClass, FalseClass] currently locked
      def _zoidberg_locked?
        @_lock && @_lock.locked?
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
        if(@_lock)
          @_lock.lock unless @_locker == ::Thread.current
          @_locker = ::Thread.current
          @_locker_count += 1
          _zoidberg_signal(:locked)
        end
        true
      end

      # Release the lock to access real instance
      #
      # @return [TrueClass]
      def _release_lock!
        if(@_lock)
          if(@_locker == ::Thread.current)
            @_locker_count -= 1
            if(@_locker_count < 1)
              @_locker = nil
              @_lock.unlock if @_lock.locked?
            end
          end
          _zoidberg_signal(:unlocked)
        end
        true
      end

      # Ensure any async threads are killed and accessing threads are
      # forced into error state.
      #
      # @return [TrueClass]
      def _zoidberg_destroy!(error=nil)
        super do
          _raw_threads[_raw_instance.object_id].map do |thread|
            thread.raise ::Zoidberg::DeadException.new('Instance in terminated state!')
          end.map do |thread|
            thread.join(2)
          end.find_all(&:alive?).map(&:kill)
          _raw_threads.delete(_raw_instance.object_id)
          @_accessing_threads.each do |thr|
            if(thr.alive?)
              begin
                thr.raise ::Zoidberg::DeadException.new('Instance in terminated state!')
              rescue
              end
            end
          end
          @_accessing_threads.clear
        end
      end

    end


  end

end
