require 'zoidberg'

module Zoidberg
  module Supervise

    class AbortException < StandardError
      attr_accessor :original_exception
    end

    class DeadException < StandardError
    end

    module InstanceMethods

      def abort(e)
        raise AbortException.new(e)
      end

    end

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
