require 'bogo'
require 'thread'
require 'securerandom'
require 'zoidberg/version'

# Why not Zoidberg!?
module Zoidberg
  autoload :DeadException, 'zoidberg/shell'
  autoload :Future, 'zoidberg/future'
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
  autoload :WeakRef, 'zoidberg/weak_ref'

  class << self

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

  end

end

# Always enable default logger
Zoidberg.logger = Zoidberg::Logger.new(STDERR)
# Set default shell to soft shell
Zoidberg.default_shell = Zoidberg::SoftShell
