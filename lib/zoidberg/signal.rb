require 'thread'
require 'zoidberg'

module Zoidberg
  # Wait/send signals
  class Signal

    include Shell

    # @return [Smash] meta information on current waiters
    attr_reader :waiters

    # Create a new instance for sending and receiving signals
    #
    # @return [self]
    def initialize
      @waiters = Smash.new
    end

    # Send a signal to _one_ waiter
    #
    # @param signal [Symbol] name of signal
    # @return [TrueClass, FalseClass] if signal was sent
    def signal(signal)
      if(@waiters[signal] && !@waiters[signal][:threads].empty?)
        @waiters[signal][:queue].push nil
        true
      else
        false
      end
    end

    # Send a signal to _all_ waiters
    #
    # @param signal [Symbol] name of signal
    # @return [TrueClass, FalseClass] if signal(s) was/were sent
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

    # Wait for a signal
    #
    # @param signal [Symbol] name of signal
    # @return [Float] number of seconds waiting for signal
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
