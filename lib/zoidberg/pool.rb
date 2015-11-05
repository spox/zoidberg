require 'zoidberg'

module Zoidberg
  # Populate a collection of instances and proxy requests to free
  # instances within the pool
  class Pool

    include Zoidberg::SoftShell

    # @return [Array<Object>] workers within pool
    attr_reader :_workers
    # @return [Signal] common signal for state updates
    attr_reader :_signal

    # Create a new pool instance. Provide class + instance
    # initialization arguments when creating the pool. These will be
    # used to build all instances within the pool.
    #
    # @return [self]
    def initialize(*args, &block)
      _validate_worker_class!(args.first)
      @_signal = Signal.new
      @_worker_count = 1
      @_workers = []
      @builder = lambda do
        inst = args.first.new(
          *args.slice(1, args.size),
          &block
        )
        inst._zoidberg_signal = _signal
        inst
      end
      _zoidberg_balance
    end

    # Validate worker class is properly supervised
    #
    # @raise [TypeError]
    def _validate_worker_class!(klass)
      unless(klass.ancestors.include?(Zoidberg::Supervise))
        raise TypeError.new "Worker class `#{klass}` must include the `Zoidberg::Supervise` module!"
      end
    end

    # Set or get the number of workers within the pool
    #
    # @param num [Integer]
    # @return [Integer]
    def _worker_count(num=nil)
      if(num)
        @_worker_count = num.to_i
        _zoidberg_balance
      end
      @_worker_count
    end

    # Balance the pool to ensure the correct number of workers are
    # available
    #
    # @return [TrueClass]
    def _zoidberg_balance
      unless(_workers.size == _worker_count)
        if(_workers.size < _worker_count)
          (_worker_count - _workers.size).times do
            _workers << @builder.call
          end
        else
          (_workers.size - _worker_count).times do
            worker = _zoidberg_free_worker
            worker._zoidberg_destroy!
            _workers.delete(worker)
          end
        end
      end
      true
    end

    # Proxy async to prevent synchronized access
    def async(*args, &block)
      worker = _workers.detect(&:_zoidberg_available?) || _workers.sample
      worker.send(:async, *args, &block)
    end

    # Used to proxy request to worker
    def method_missing(*args, &block)
      worker = _zoidberg_free_worker
      current_self._release_lock!
      begin
        worker.send(*args, &block)
      rescue Zoidberg::DeadException => e
        if(e.origin_object_id == object_id)
          raise e
        else
          abort e
        end
      rescue => e
        abort e
      end
    end

    # Find or wait for a free worker
    #
    # @return [Object]
    def _zoidberg_free_worker
      unless(worker = _workers.detect(&:_zoidberg_available?))
        until((worker = _signal.wait_for(:unlocked))._zoidberg_available?); end
      end
      worker
    end

    # Force termination of all workers when terminated
    def terminate
      @_workers.map(&:_zoidberg_destroy!)
    end

  end
end
