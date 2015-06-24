require 'zoidberg'

module Zoidberg
  # Populate a collection of instances and proxy requests to free
  # instances within the pool
  class Pool

    include Zoidberg::Shell

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

    # Used to proxy request to worker
    def method_missing(*args, &block)
      worker = _zoidberg_free_worker
      defer{ worker.send(*args, &block) }
    end

    # Find or wait for a free worker
    #
    # @return [Object]
    def _zoidberg_free_worker
      until(worker = @_workers.detect(&:_zoidberg_available?))
        defer{ _signal.wait_for(:unlocked) }
      end
      worker
    end

  end
end
