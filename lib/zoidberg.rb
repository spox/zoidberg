require 'bogo'
require 'zoidberg/version'

# Why not Zoidberg!?
module Zoidberg
  autoload :Future, 'zoidberg/future'
  autoload :Pool, 'zoidberg/pool'
  autoload :Proxy, 'zoidberg/proxy'
  autoload :Shell, 'zoidberg/shell'
  autoload :Signal, 'zoidberg/signal'
  autoload :Supervise, 'zoidberg/supervise'
end
