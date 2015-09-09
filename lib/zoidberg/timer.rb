require 'zoidberg'

module Zoidberg

  # Simple timer class
  class Timer

    include Zoidberg::SoftShell

    # Custom exception used to wakeup timer
    class Wakeup < StandardError; end

    # @return [Mutex]
    attr_reader :notify_locker
    # @return [Array<Smash>] items to run
    attr_reader :to_run
    # @return [TrueClass, FalseClass] timer is paused
    attr_reader :paused

    # Create a new timer
    #
    # @return [self]
    def initialize
      @to_run = []
      @notify_locker = Mutex.new
      @paused = false
      @thread = Thread.new{ run! }
    end

    # Run recurring action at given interval
    #
    # @param interval [Numeric]
    # @yield action to run
    # @return [self]
    def every(interval, &block)
      to_run.push(
        Smash.new(
          :interval => interval,
          :action => block,
          :last_run => Time.now.to_f,
          :recur => true
        )
      )
      reset
      current_self
    end

    # Run action after given interval
    #
    # @param interval [Numeric]
    # @yield action to run
    # @return [self]
    def after(interval, &block)
      to_run.push(
        Smash.new(
          :interval => interval,
          :action => block,
          :last_run => Time.now.to_f
        )
      )
      reset
      current_self
    end

    # Pause the timer to prevent any actions from being run
    #
    # @return [self]
    def pause
      unless(@paused)
        @paused = true
        reset
      end
      current_self
    end

    # Resume a paused timer
    #
    # @return [self]
    def resume
      if(@paused)
        @paused = false
        reset
      end
      current_self
    end

    # Remove all actions from the timer
    #
    # @return [self]
    def cancel
      to_run.clear
      reset
      current_self
    end

    # Reset the timer
    #
    # @param wakeup [TrueClass, FalseClass] wakeup the timer thread
    # @return [self]
    def reset(wakeup=true)
      to_run.sort_by! do |item|
        Time.now.to_f - (item[:interval] + item[:last_run])
      end
      if(wakeup)
        notify_locker.synchronize do
          @thread.raise Wakeup.new
        end
      end
      current_self
    end

    # @return [Numeric, NilClass] interval to next action
    def next_interval
      notify_locker.synchronize do
        unless(to_run.empty? || paused)
          item = to_run.first
          result = Time.now.to_f - (item[:last_run] + item[:interval])
          result < 0 ? 0 : result
        end
      end
    end

    # Run any actions that are ready
    #
    # @return [self]
    def run_ready
      items = to_run.find_all do |item|
        (Time.now.to_f - (item[:interval] + item[:last_run])) <= 0
      end
      to_run.delete_if do |item|
        items.include?(item)
      end
      items.map do |item|
        begin
          item[:action].call
        rescue DeadException
          item[:recur] = false
        rescue => e
          Zoidberg.logger.error "<#{self}> Timed action generated an error: #{e.class.name} - #{e}"
        end
        if(item[:recur])
          item[:last_run] = Time.now.to_f
          item
        end
      end.compact.each do |item|
        to_run << item
      end
      current_self
    end

    protected

    # Run the timer loop
    def run!
      loop do
        begin
          sleep _zoidberg_proxy.next_interval
          notify_locker.synchronize do
            _zoidberg_proxy.run_ready
            _zoidberg_proxy.reset(false)
          end
        rescue Wakeup
          Zoidberg.logger.debug "<#{self}> Received wakeup notification. Rechecking sleep interval!"
        rescue DeadException
          raise
        rescue => e
          Zoidberg.logger.error "<#{self}> Unexpected error in runner: #{e.class.name} - #{e}"
          Zoidberg.logger.debug "<#{self}> #{e.class.name}: #{e}\n#{e.backtrace.join("\n")}"
          current_self.raise e
        end
      end
    end

  end

end
