require 'zoidberg'

module Zoidberg
  class Proxy

    class Liberated < Proxy

      # Time allowed for threads to gracefully die
      THREAD_KILL_AFTER = 5

      # @return [Thread] current owner of lock
      attr_reader :_locker
      # @return [Concurrent::CachedThreadPool]
      attr_reader :_thread_pool

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
        @_thread_pool = ::Concurrent::CachedThreadPool.new
        @_supervised = klass.ancestors.include?(::Zoidberg::Supervise)
      end

      # Used to proxy request to real instance
      def method_missing(*args, &block)
        res = nil
        @_accessing_threads << ::Thread.current
        begin
          _aquire_lock!
          @got_lock = true
          if(::ENV['ZOIDBERG_TESTING'])
            timer = ::Thread.new(::Thread.current) do |origin|
              begin
                time = ::ENV.fetch('ZOIDBERG_TESTING_TIMEOUT', 5).to_i
                ::Timeout.timeout(time) do
                  ::Kernel.sleep(time)
                end
                nil
              rescue => error
                error
              end
            end
            res = @_raw_instance.__send__(*args, &block)
            if(timer.alive?)
              timer.kill
            else
              val = timer.value
              if(val.is_a?(Exception))
                raise val
              end
            end
          else
            res = @_raw_instance.__send__(*args, &block)
          end
        rescue ::Zoidberg::AbortException => e
          ::Kernel.raise e.original_exception
        rescue ::Exception => e
          ::Zoidberg.logger.debug "Exception on: #{_raw_instance.class.name}##{args.first}(#{args.slice(1, args.size).map(&:inspect).join(', ')})"
          _zoidberg_unexpected_error(e)
          ::Kernel.raise e
        ensure
          if(@got_lock)
            _release_lock!
            t_idx = @_accessing_threads.index(::Thread.current)
            @_accessing_threads.delete_at(t_idx) if t_idx
          end
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
        super do
          if(@_lock)
            if(::ENV['ZOIDBERG_DEBUG'] == 'true')
              ::Timeout.timeout(::ENV.fetch('ZOIDBERG_DEBUG_TIMEOUT', 10).to_i) do
                @_lock.lock unless @_locker == ::Thread.current
              end
            else
              @_lock.lock unless @_locker == ::Thread.current
            end
            @_locker = ::Thread.current
            @_locker_count += 1
          end
          true
        end
      end

      # Release the lock to access real instance
      #
      # @return [TrueClass]
      def _release_lock!
        super do
          if(@_lock && @_locker == ::Thread.current)
            @_locker_count -= 1
            if(@_locker_count < 1)
              @_locker = nil
              @_lock.unlock if @_lock.locked?
            end
          else
            false
          end
        end
      end

      # Ensure any async threads are killed and accessing threads are
      # forced into error state.
      #
      # @return [TrueClass]
      def _zoidberg_destroy!(error=nil)
        object_string = self.inspect
        oid = _raw_instance.object_id
        ::Zoidberg.logger.debug "*** Destroying zoidberg instance #{object_string}"
        super do
          _thread_pool.shutdown
          unless(_thread_pool.wait_for_termination(2))
            _thread_pool.kill
          end
          @_accessing_threads.each do |thread|
            if(thread.alive?)
              begin
                thread.raise ::Zoidberg::DeadException.new('Instance in terminated state!', oid)
                ::Thread.new(thread) do |thread|
                  next if thread == ::Thread.current
                  thread.join(::Zoidberg::Proxy::Liberated::THREAD_KILL_AFTER)
                  if(thread.alive?)
                    ::Zoidberg.logger.error "Failed to halt accessing thread, killing: #{thread.inspect}"
                    thread.kill
                  end
                end
              rescue
              end
            end
          end
          @_accessing_threads.clear
        end
        ::Zoidberg.logger.debug "!!! Destroyed zoidberg instance #{object_string}"
      end

    end


  end

end
