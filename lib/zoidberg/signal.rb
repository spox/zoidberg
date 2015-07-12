require 'thread'
require 'zoidberg'

module Zoidberg
  # Wait/send signals
  class Signal

    # empty value when no object is provided
    EMPTY_VALUE = :_zoidberg_empty_

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
    # @param obj [Object] optional Object to send
    # @return [TrueClass, FalseClass] if signal was sent
    def signal(signal, obj=EMPTY_VALUE)
      if(@waiters[signal]) # && !@waiters[signal][:threads].empty?)
        @waiters[signal][:queue].push obj
        true
      else
        false
      end
    end

    # Send a signal to _all_ waiters
    #
    # @param signal [Symbol] name of signal
    # @param obj [Object] optional Object to send
    # @return [TrueClass, FalseClass] if signal(s) was/were sent
    def broadcast(signal, obj=EMPTY_VALUE)
      if(@waiters[signal]) # && !@waiters[signal][:threads].empty?)
        @waiters[signal][:threads].size.times do
          @waiters[signal][:queue].push obj
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
      val = defer{ @waiters[signal][:queue].pop }
      @waiters[signal][:threads].delete(Thread.current)
      val == EMPTY_VALUE ? (Time.now.to_f - start_sleep) : val
    end

  end
end
