require 'zoidberg'

module Zoidberg

  # Simple timer class
  class Timer

    class Action

      # @return [TrueClass, FalseClass]
      attr_reader :recur
      # @return [Proc] action to run
      attr_reader :action
      # @return [Numeric]
      attr_reader :interval
      # @return [Float]
      attr_reader :last_run

      # Create a new action
      #
      # @param args [Hash]
      # @option args [Numeric] :interval
      # @option args [TrueClass, FalseClass] :recur
      # @return [self]
      def initialize(args={}, &block)
        unless(block)
          raise ArgumentError.new 'Action is required. Block must be provided!'
        end
        @action = block
        @recur = args.fetch(:recur, false)
        @interval = args.fetch(:interval, 5)
        @last_run = Time.now.to_f
        @cancel = false
      end

      # Cancel the action
      #
      # @return [TrueClass]
      def cancel
        @recur = false
        @cancel = true
      end

      # @return [TrueClass, FalseClass]
      def cancelled?
        @cancel
      end

      # Run the action
      #
      # @return [self]
      def run!
        @last_run = Time.now.to_f
        action.call
        @last_run = Time.now.to_f
        self
      end

    end

    include Zoidberg::SoftShell

    # Custom exception used to wakeup timer
    class Wakeup < StandardError; end

    # @return [Mutex]
    attr_reader :notify_locker
    # @return [Array<Action>] items to run
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
    # @return [Action]
    def every(interval, &block)
      action = Action.new({
          :interval => interval,
          :recur => true
        },
        &block
      )
      to_run.push(action)
      reset
      action
    end

    # Run action after given interval
    #
    # @param interval [Numeric]
    # @yield action to run
    # @return [Action]
    def after(interval, &block)
      action = Action.new(
        {:interval => interval},
        &block
      )
      to_run.push(action)
      reset
      action
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
      if(wakeup)
        notify_locker.synchronize do
          to_run.sort_by! do |item|
            (item.interval + item.last_run) - Time.now.to_f
          end
          @thread.raise Wakeup.new
        end
      else
        to_run.sort_by! do |item|
          (item.interval + item.last_run) - Time.now.to_f
        end
      end
      current_self
    end

    # @return [Numeric, NilClass] interval to next action
    def next_interval
      unless(to_run.empty? || paused)
        item = to_run.first
        result = (item.last_run + item.interval) - Time.now.to_f
        result < 0 ? 0 : result
      end
    end

    # Run any actions that are ready
    #
    # @return [self]
    def run_ready
      items = to_run.find_all do |item|
        ((item.interval + item.last_run) - Time.now.to_f) <= 0
      end
      to_run.delete_if do |item|
        items.include?(item)
      end
      items.map do |item|
        begin
          item.run! unless item.cancelled?
        rescue DeadException
          item.cancel
        rescue => e
          Zoidberg.logger.error "<#{self}> Timed action generated an error: #{e.class.name} - #{e}"
        end
        item if item.recur
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
          interval = nil
          # TODO: update with select for better subsecond support
          notify_locker.synchronize do
            interval = next_interval
          end
          sleep interval
          notify_locker.synchronize do
            run_ready
            reset(false)
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
