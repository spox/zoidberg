require 'thread'
require 'zoidberg'

module Zoidberg
  class Signal

    include Shell

    attr_reader :waiters

    def initialize
      @waiters = Smash.new
    end

    def signal(signal)
      if(@waiters[signal] && !@waiters[signal][:threads].empty?)
        @waiters[signal][:queue].push nil
        true
      else
        false
      end
    end

    def broadcast(signal)
      if(@waiters[signal] && !@waiters[signal][:threads].empty?)
        @waiters[signal][:threads].times do
          @waiters[signal][:queue].push nil
        end
        true
      else
        false
      end
    end

    def wait_for(signal)
      @waiters[signal] ||= Smash.new(
        :queue => Queue.new,
        :threads => []
      )
      start_sleep = Time.now.to_f
      @waiters[signal][:threads].push(Thread.current)
      defer{ @waiters[signal][:queue].pop }
      @waiters[signal][:threads].delete(Thread.current)
      Time.now.to_f - start_sleep
    end

  end
end
