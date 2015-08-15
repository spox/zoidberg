require 'bogo'
require 'thread'
require 'zoidberg/version'

# Why not Zoidberg!?
module Zoidberg
  autoload :DeadException, 'zoidberg/shell'
  autoload :Future, 'zoidberg/future'
  autoload :Pool, 'zoidberg/pool'
  autoload :Proxy, 'zoidberg/proxy'
  autoload :Registry, 'zoidberg/registry'
  autoload :Shell, 'zoidberg/shell'
  autoload :Signal, 'zoidberg/signal'
  autoload :Supervise, 'zoidberg/supervise'
  autoload :Supervisor, 'zoidberg/supervisor'
  autoload :WeakRef, 'zoidberg/weak_ref'
end
