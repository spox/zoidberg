require 'zoidberg'

module Zoidberg

  # Run a task
  class Task

    # Supported task styles
    SUPPORTED_STYLES = [:serial, :async]

    # @return [Symbol] :fiber or :thread
    attr_reader :style
    # @return [Object] originator of task
    attr_reader :origin
    # @return [Proc] block to execute
    attr_reader :content
    attr_reader :content_arguments
    # @return [Thread, Fiber] underlying task container
    attr_reader :task

    # Create a new task
    #
    # @param task_style [Symbol]
    # @param origin [Object] origin object of block
    # @yield block to execute
    # @return [self]
    def initialize(task_style, origin, block_args=[], &block)
      unless(SUPPORTED_STYLES.include?(task_style))
        raise ArgumentError.new("Allowed style values: #{SUPPORTED_STYLES.map(&:inspect).join(', ')} but received: #{task_style.inspect}")
      end
      @style = task_style
      @origin = origin
      @content = block
      @content_arguments = block_args
      @result = nil
      send("run_#{style}")
    end

    # @return [Object] result of task
    def value
      if(task.alive?)
        @result = style == :async ? task.join : task.resume
      end
      @result
    end

    # Force task to stop prior to completion if still in running state
    #
    # @return [NilClass]
    def halt!
      if(style == :async)
        task.kill
      else
        @task = nil
      end
    end

    # @return [TrueClass, FalseClass] task currently waiting to run
    def waiting?
      task && task.alive? && task.respond_to?(:stop?) ? task.stop? : true
    end

    # @return [TrueClass, FalseClass] task is running
    def running?
      if(task)
        style == :async && task.alive? && !task.stop?
      else
        false
      end
    end

    # @return [TrueClass, FalseClass] task is complete
    def complete?
      task.nil? || !task.alive?
    end

    # @return [TrueClass, FalseClass] task complete in error state
    def error?
      complete? && value.is_a?(Exception)
    end

    # @return [TrueClass, FalseClass] task complete in success state
    def success?
      complete? && !error?
    end

    # Reliquish running state and return optional value(s)
    #
    # @param args [Object] values to return
    # @return [Object, Array<Object>]
    def cease(*args)
      if(style == :async)
        task[:task_args] = args
        task.stop
        task[:task_args]
      else
        Fiber.yield(*args)
      end
    end

    # Regain running state with optional value(s)
    # @param args [Object] values to provide
    # @return [Object, Array<Object>]
    def proceed(*args)
      if(style == :serial)
        task.resume(*args)
      else
        task[:task_args] = args
        task.run
        task[:task_args]
      end
    end

    protected

    # Create new fiber based task
    #
    # @return [Fiber]
    def run_serial
      @task = Fiber.new do
        begin
          self.instance_exec(*content_arguments, &content)
        rescue Exception => e
          origin.send(:raise, e)
          raise
        end
      end
    end

    # Create new thread based task
    #
    # @return [Thread]
    def run_async
      @task = Thread.new do
        Thread.stop
        begin
          self.instance_exec(*content_arguments, &content)
        rescue Exception => e
          origin.send(:raise, e)
          raise
        end
      end
      until(@task.stop?)
        sleep(0.01)
      end
      @task
    end

  end

end
