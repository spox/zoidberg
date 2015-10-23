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
      alias_method :canceled?, :cancelled?

      # Run the action
      #
      # @return [self]
      def run!
        unless(cancelled?)
          @last_run = Time.now.to_f
          action.call
          @last_run = Time.now.to_f
        end
        self
      end

      # @return [TrueClass, FalseClass]
      def ready?
        Time.now.to_f > (
          last_run + interval
        )
      end

    end

    include Zoidberg::SoftShell

    # Wakeup string
    WAKEUP = "WAKEUP\n"

    # @return [Array<Action>] items to run
    attr_reader :to_run
    # @return [TrueClass, FalseClass] timer is paused
    attr_reader :paused
    # @return [IO]
    attr_reader :waker
    # @return [IO]
    attr_reader :alerter

    # Create a new timer
    #
    # @return [self]
    def initialize
      @to_run = []
      @paused = false
      @alerter, @waker = IO.pipe
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
      to_run.sort_by! do |item|
        (item.interval + item.last_run) - Time.now.to_f
      end
      if(wakeup)
        waker.write WAKEUP
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
      items = to_run.find_all(&:ready?)
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

    # Clean up timer thread
    def terminate
      @thread.raise Zoidberg::DeadException.new('Instance in terminated state', object_id)
    end

    protected

    # Run the timer loop
    def run!
      loop do
        begin
          alerter.read_nonblock(WAKEUP.length)
        rescue IO::WaitReadable
          interval = current_self.next_interval if current_self
          IO.select([alerter], [], [], interval)
        end
        begin
          run_ready
          reset(false)
        rescue DeadException => e
          if(e.origin_object_id == object_id)
            Zoidberg.logger.debug "<#{self}> Terminated state encountered. Falling out of run loop!"
            raise
          else
            current_self.raise e
          end
        rescue => e
          Zoidberg.logger.error "<#{self}> Unexpected error in runner: #{e.class.name} - #{e}"
          Zoidberg.logger.debug "<#{self}> #{e.class.name}: #{e}\n#{e.backtrace.join("\n")}"
          current_self.raise e
        end
      end
    end

  end

end
