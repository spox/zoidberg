require 'zoidberg'

module Zoidberg

  # Instance proxy that filters requests to shelled instance
  class Proxy < BasicObject

    autoload :Confined, 'zoidberg/proxy/confined'
    autoload :Liberated, 'zoidberg/proxy/liberated'

    class << self
      @@__registry = ::Hash.new

      # @return [Hash] WeakRef -> Proxy mapping
      def registry
        @@__registry
      end

      # Register the proxy a WeakRef is pointing to
      #
      # @param r_id [Integer] object ID of WeakRef
      # @param proxy [Zoidberg::Proxy] actual proxy instance
      # @return [Zoidberg::Proxy]
      def register(r_id, proxy)
        @@__registry[r_id] = proxy
      end

      # Destroy the proxy referenced by the WeakRef with the provided
      # ID
      #
      # @param o_id [Integer] Object ID
      # @return [Truthy, Falsey]
      def scrub!(o_id)
        proxy = @@__registry.delete(o_id)
        if(proxy)
          proxy._zoidberg_destroy!
        end
      end
    end

    # Setup proxy for proper scrubbing support
    def self.inherited(klass)
      klass.class_eval do
        # @return [Array] arguments used to build real instance
        attr_accessor :_build_args
        # @return [Object] wrapped instance
        attr_reader :_raw_instance
      end
    end

    # Abstract class gets no builder
    def initialize(*_)
      raise NotImplementedError
    end

    # @return [TrueClass, FalseClass] currently locked
    def _zoidberg_locked?
      false
    end

    # @return [TrueClass, FalseClass] currently unlocked
    def _zoidberg_available?
      !_zoidberg_locked?
    end

    # @return [Object]
    def _zoidberg_link=(inst)
      @_zoidberg_link = inst
    end

    # @return [Object, NilClass]
    def _zoidberg_link
      @_zoidberg_link
    end

    # Set an optional state signal instance
    #
    # @param signal [Signal]
    # @return [Signal]
    def _zoidberg_signal=(signal)
      @_zoidberg_signal = signal
    end

    # Send a signal if the optional signal instance has been set
    #
    # @param sig [Symbol]
    # @return [TrueClass, FalseClass] signal was sent
    def _zoidberg_signal(sig)
      if(@_zoidberg_signal)
        @_zoidberg_signal.signal(sig)
        true
      else
        false
      end
    end

    # Properly handle an unexpected exception when encountered
    #
    # @param e [Exception]
    def _zoidberg_unexpected_error(e)
      ::Zoidberg.logger.error "Unexpected exception: #{e.class} - #{e}"
      unless((defined?(Timeout) && e.is_a?(Timeout::Error)) || e.is_a?(::Zoidberg::DeadException))
        if(_zoidberg_link)
          if(_zoidberg_link.class.trap_exit)
            ::Zoidberg.logger.warn "Calling linked exit trapper #{@_raw_instance.class.name} -> #{_zoidberg_link.class}: #{e.class} - #{e}"
            _zoidberg_link.async.send(
              _zoidberg_link.class.trap_exit, @_raw_instance, e
            )
          end
        else
          if(@_supervised)
            ::Zoidberg.logger.warn "Unexpected error for supervised class `#{@_raw_instance.class.name}`. Handling error (#{e.class} - #{e})"
            ::Zoidberg.logger.debug "#{e.class}: #{e}\n#{e.backtrace.join("\n")}"
            _zoidberg_handle_unexpected_error(e)
          end
        end
      end
    end

    # When real instance is being supervised, unexpected exceptions
    # will force the real instance to be terminated and replaced with
    # a fresh instance. If the real instance provides a #restart
    # method that will be called instead of forcibly terminating the
    # current real instance and rebuild a new instance.
    #
    # @param error [Exception] exception that was caught
    # @return [TrueClass]
    def _zoidberg_handle_unexpected_error(error)
      if(_raw_instance.respond_to?(:restart))
        begin
          _raw_instance.restart(error)
          return # short circuit
        rescue => e
        end
      end
      _zoidberg_destroy!
      _aquire_lock!
      args = _build_args.dup
      @_raw_instance = args.shift.unshelled_new(
        *args.first,
        &args.last
      )
      _raw_instance._zoidberg_proxy(self)
      _release_lock!
      true
    end

    # Destroy the real instance. Will update all methods on real
    # instance to raise exceptions noting it as terminated rendering
    # it unusable. This is generally used with the supervise module
    # but can be used on its own if desired.
    #
    # @return [TrueClass]
    def _zoidberg_destroy!(error=nil, &block)
      unless(_raw_instance.respond_to?(:_zoidberg_destroyed))
        if(_raw_instance.respond_to?(:terminate))
          if(_raw_instance.method(:terminate).arity == 0)
            _raw_instance.terminate
          else
            _raw_instance.terminate(error)
          end
        end
        death_from_above = ::Proc.new do
          ::Kernel.raise ::Zoidberg::DeadException.new('Instance in terminated state!')
        end
        death_from_above_display = ::Proc.new do
          "#<#{self.class.name}:TERMINATED>"
        end
        block.call if block
        _raw_instance.instance_variables.each do |i_var|
          _raw_instance.remove_instance_variable(i_var)
        end
        (
          _raw_instance.public_methods(false) +
          _raw_instance.protected_methods(false) +
          _raw_instance.private_methods(false)
        ).each do |m_name|
          next if m_name.to_sym == :alive?
          _raw_instance.send(:define_singleton_method, m_name, &death_from_above)
        end
        _raw_instance.send(:define_singleton_method, :to_s, &death_from_above_display)
        _raw_instance.send(:define_singleton_method, :inspect, &death_from_above_display)
        _raw_instance.send(:define_singleton_method, :_zoidberg_destroyed, ::Proc.new{ true })
        _zoidberg_signal(:destroyed)
      end
      true
    end
    alias_method :terminate, :_zoidberg_destroy!

    # @return [self]
    def _zoidberg_object
      self
    end

  end
end

# jruby compat [https://github.com/jruby/jruby/pull/2520]
if(Zoidberg::Proxy.instance_methods.include?(:object_id))
  class Zoidberg::Proxy
    undef_method :object_id
  end
end
