require 'zoidberg'

module Zoidberg
  # Add supervision to instance
  module Supervise

    # Include supervision into given class when included
    #
    # @param klass [Class]
    def self.included(klass)
      unless(klass.include?(Zoidberg::Shell))
        klass.class_eval{ include Zoidberg::Shell }
      end
    end

  end
end
