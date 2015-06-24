require 'zoidberg'

module Zoidberg
  # Provide weak reference to object allowing for it to be garbage
  # collected. This is a stripped down version of the ::WeakRef class
  class WeakRef < BasicObject

    # Exception type raised when referenced object no longer exists
    class RecycledException < ::RuntimeError
      # @return [String] ID of referenced object casted to string
      attr_reader :recycled_object_id
      # Create a new exception instance
      #
      # @param msg [String] exception message
      # @param recycled_object_id [String] casted object ID
      # @return [self]
      def initialize(msg, recycled_object_id)
        @recycled_object_id = recycled_object_id
        super(msg)
      end
    end

    @@__zoidberg_map = ::ObjectSpace::WeakMap.new

    # Create a new weak reference
    #
    # @param orig [Object] referenced object
    # @return [self]
    def initialize(orig)
      @_key = orig.object_id.to_s
      @@__zoidberg_map[@_key] = orig
    end

    def method_missing(*args, &block) # :nodoc:
      if(@@__zoidberg_map[@_key])
        @@__zoidberg_map[@_key].__send__(*args, &block)
      else
        ::Kernel.raise RecycledException.new('Instance has been recycled by the system!', @_key)
      end
    end

  end

end

# jruby compat
if(Zoidberg::WeakRef.instance_methods.include?(:object_id))
  class Zoidberg::WeakRef
    undef_method :object_id
  end
end
