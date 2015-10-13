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
        @_raw_threads = ::Smash.new{ ::Array.new }
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
        rescue ::Zoidberg::Supervise::AbortException => e
          ::Kernel.raise e.original_exception
        rescue ::Exception => e
          ::Zoidberg.logger.debug "Exception on: #{_raw_instance.class.name}##{args.first}(#{args.slice(1, args.size).map(&:inspect).join(', ')})"
          _zoidberg_unexpected_error(e)
          if(e.class.to_s == 'fatal' && !@_fatal_retry)
            @_fatal_retry = true
            retry
          else
            ::Kernel.raise e
          end
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

      # Register a running thread for this instance. Registered
      # threads are tracked and killed on cleanup
      #
      # @param thread [Thread]
      # @return [TrueClass]
      def _zoidberg_thread(thread)
        _raw_threads[self.object_id].push(thread)
        true
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
