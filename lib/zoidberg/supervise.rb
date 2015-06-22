require 'zoidberg'

module Zoidberg
  # Add supervision to instance
  module Supervise
    # Customized exception type to wrap allowed errors
    class AbortException < StandardError
      attr_accessor :original_exception
    end

    # Customized exception type used when instance has been terminated
    class DeadException < StandardError
    end

    module InstanceMethods

      # Customized method for raising exceptions that have been
      # properly handled (preventing termination)
      #
      # @param e [Exception]
      # @raises [AbortException]
      def abort(e)
        raise AbortException.new(e)
      end

    end

    # Include supervision into given class when included
    #
    # @param klass [Class]
    def self.included(klass)
      unless(klass.ancestors.include?(Zoidberg::Supervise))
        klass.class_eval do
          include Zoidberg::Shell
          include InstanceMethods
        end
      end
    end

  end
end
