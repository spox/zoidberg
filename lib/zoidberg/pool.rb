require 'zoidberg'

module Zoidberg
  class Pool

    include Zoidberg::Shell

    attr_reader :_workers
    attr_reader :_signal

    def initialize(*args, &block)
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

    def _worker_count(num=nil)
      if(num)
        @_worker_count = num.to_i
        _zoidberg_balance
      end
      @_worker_count
    end

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

    def method_missing(*args, &block)
      worker = _zoidberg_free_worker
      defer{ worker.send(*args, &block) }
    end

    def _zoidberg_free_worker
      until(worker = @_workers.detect(&:_zoidberg_available?))
        defer{ _signal.wait_for(:unlocked)}
      end
      worker
    end

  end
end
