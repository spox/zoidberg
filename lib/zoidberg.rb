require 'bogo'
require 'securerandom'
require 'concurrent'
require 'concurrent-edge'

require 'zoidberg/version'

# Why not Zoidberg!?
module Zoidberg
  autoload :DeadException, 'zoidberg/shell'
  autoload :Future, 'zoidberg/future'
  autoload :Lazy, 'zoidberg/lazy'
  autoload :Logger, 'zoidberg/logger'
  autoload :Pool, 'zoidberg/pool'
  autoload :Proxy, 'zoidberg/proxy'
  autoload :Registry, 'zoidberg/registry'
  autoload :Shell, 'zoidberg/shell'
  autoload :SoftShell, 'zoidberg/shell'
  autoload :HardShell, 'zoidberg/shell'
  autoload :Signal, 'zoidberg/signal'
  autoload :Supervise, 'zoidberg/supervise'
  autoload :Supervisor, 'zoidberg/supervisor'
  autoload :Task, 'zoidberg/task'
  autoload :Timer, 'zoidberg/timer'
  autoload :WeakRef, 'zoidberg/weak_ref'

  class << self

    # @return [TrueClass, FalseClass]
    attr_reader :signal_shutdown
    # @return [Module]
    attr_accessor :default_shell

    # @return [Zoidberg::Logger]
    def logger
      @zoidberg_logger
    end

    # Set new default logger
    #
    # @param log [Zoidberg::Logger]
    # @return [zoidberg::Logger]
    def logger=(log)
      unless(log.is_a?(Zoidberg::Logger))
        raise TypeError.new "Expecting type `Zoidberg::Logger` but received type `#{log.class}`"
      end
      @zoidberg_logger = log
    end

    # @return [String] UUID
    def uuid
      SecureRandom.uuid
    end

    # Flag shutdown state
    #
    # @param val [Truthy, Falsey]
    # @return [TrueClass, FalseClass]
    def signal_shutdown=(val)
      @signal_shutdown = !!val
      # NOTE: Manually call registered at exit items to force
      # global thread pools and related structures to be shut
      # down. Wrapped in a thread to prevent locking issues
      # when set within trap context
      Thread.new{ Concurrent.const_get(:AtExit).run } if val
      @signal_shutdown
    end

    # Reset shutdown state
    #
    # @return [FalseClass]
    def signal_reset
      self.signal_shutdown = false
    end

    # @return [TrueClass, FalseClass]
    def in_shutdown?
      !!self.signal_shutdown
    end

  end

end

# Always enable default logger
Zoidberg.logger = Zoidberg::Logger.new(STDERR)
# Set default shell to soft shell
Zoidberg.default_shell = Zoidberg::SoftShell

%w(INT TERM).each do |sig_name|
  original = Signal.trap(sig_name) do |*_|
    Zoidberg.signal_shutdown = true unless ENV['ZOIDBERG_TESTING']
    original.call if original.respond_to?(:call)
  end
end

if(::ENV['ZOIDBERG_TESTING'])
  ::Kernel.require 'timeout'
end
