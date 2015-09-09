require 'thread'
require 'zoidberg'

module Zoidberg
  # Wait/send signals
  class Signal

    # empty value when no object is provided
    EMPTY_VALUE = :_zoidberg_empty_

    include SoftShell

    # @return [Smash] meta information on current waiters
    attr_reader :waiters
    # @return [TrueClass, FalseClass]
    attr_reader :cache_signals

    # Create a new instance for sending and receiving signals
    #
    # @param args [Hash] options
    # @return [self]
    def initialize(args={})
      @cache_signals = args.fetch(:cache_signals, false)
      @waiters = Smash.new
    end

    # Set cache behavior
    #
    # @param arg [TrueClass, FalseClass] set behavior
    # @return [TrueClass, FalseClass] behavior
    def cache_signals(arg=nil)
      unless(arg.nil?)
        @cache_signals = !!arg
      end
      @cache_signals
    end

    # Send a signal to _one_ waiter
    #
    # @param signal [Symbol] name of signal
    # @param obj [Object] optional Object to send
    # @return [TrueClass, FalseClass] if signal was sent
    def signal(signal, obj=EMPTY_VALUE)
      if(signal_init(signal, :signal))
        waiters[signal][:queue].push obj
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
      if(signal_init(signal, :signal))
        num = waiters[signal][:threads].size
        num = 1 if num < 1
        num.times do
          waiters[signal][:queue].push obj
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
      signal_init(signal, :wait)
      start_sleep = Time.now.to_f
      waiters[signal][:threads].push(Thread.current)
      val = defer{ waiters[signal][:queue].pop }
      waiters[signal][:threads].delete(Thread.current)
      val == EMPTY_VALUE ? (Time.now.to_f - start_sleep) : val
    end

    protected

    # Initialize the signal structure data
    #
    # @param name [String, Symbol] name of signal
    # @param origin [String] origin of init
    # @return [TrueClass, FalseClass]
    def signal_init(name, origin)
      if(waiters[name])
        cache_signals ||
          origin == :wait ||
          (origin == :signal && !waiters[name][:threads].empty?)
      else
        if(origin == :wait || (origin == :signal && cache_signals))
          waiters[name] = Smash.new(
            :queue => Queue.new,
            :threads => []
          )
          true
        else
          false
        end
      end
    end

  end
end
