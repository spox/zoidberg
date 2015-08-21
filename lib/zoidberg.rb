require 'bogo'
require 'thread'
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
  autoload :Signal, 'zoidberg/signal'
  autoload :Supervise, 'zoidberg/supervise'
  autoload :Supervisor, 'zoidberg/supervisor'
  autoload :WeakRef, 'zoidberg/weak_ref'

  class << self

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

  end

end

# Always enable default logger
Zoidberg.logger = Zoidberg::Logger.new(STDOUT)
