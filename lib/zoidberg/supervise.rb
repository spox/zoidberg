require 'zoidberg'

module Zoidberg
  # Add supervision to instance
  module Supervise
    # Customized exception type to wrap allowed errors
    class AbortException < StandardError
      attr_accessor :original_exception

      def to_s
        if(original_exception)
          "#{original_exception.class}: #{original_exception}"
        else
          super
        end
      end
    end

    module InstanceMethods

      # Customized method for raising exceptions that have been
      # properly handled (preventing termination)
      #
      # @param e [Exception]
      # @raises [AbortException]
      def abort(e)
        unless(e.is_a?(::Exception))
          e = StandardError.new(e)
        end
        new_e = ::Zoidberg::Supervise::AbortException.new
        new_e.original_exception = e
        ::Kernel.raise new_e
      end

    end

    # Include supervision into given class when included
    #
    # @param klass [Class]
    def self.included(klass)
      unless(klass.include?(Zoidberg::Shell))
        klass.class_eval{ include Zoidberg::Shell }
      end
      unless(klass.include?(Zoidberg::Supervise::InstanceMethods))
        klass.class_eval do
          include InstanceMethods
        end
      end
    end

  end
end
