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

    def _zoidberg_unsupervise
      @_supervised = false
    end

    # Set the raw instance into the proxy and link proxy to instance
    #
    # @param inst [Object] raw instance being wrapped
    # @return [NilClass]
    def _zoidberg_set_instance(inst)
      @_raw_instance = inst
      @_raw_instance._zoidberg_proxy(self)
      nil
    end

    # @return [TrueClass, FalseClass] currently locked
    def _zoidberg_locked?
      false
    end

    # @return [TrueClass]
    def _aquire_lock!(&block)
      result = block ? block.call : true
      _zoidberg_signal(:locked)
      result
    end

    # @return [TrueClass]
    def _release_lock!(&block)
      result = block ? block.call : true
      _zoidberg_signal(:unlocked, self) if _zoidberg_available?
      result
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
    def _zoidberg_signal(*args)
      if(@_zoidberg_signal)
        @_zoidberg_signal.signal(*args)
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
      ::Zoidberg.logger.debug "#{e.class}: #{e}\n#{e.backtrace.join("\n")}"
      if(_zoidberg_link)
        if(_zoidberg_link.class.trap_exit)
          ::Zoidberg.logger.warn "Calling linked exit trapper #{@_raw_instance.class.name} -> #{_zoidberg_link.class}: #{e.class} - #{e}"
          _zoidberg_link.async.send(
            _zoidberg_link.class.trap_exit, @_raw_instance, e
          )
        end
      else
        _zoidberg_handle_unexpected_error(e)
      end
    end

    # When real instance is being supervised, unexpected exceptions
    # will force the real instance to be terminated and replaced with
    # a fresh instance.
    #
    # If the real instance provides a #restart
    # method that will be called instead of forcibly terminating the
    # current real instance and rebuild a new instance.
    #
    # If the real instance provides a #restarted! method, that method
    # will be called on the newly created instance on replacement
    #
    # @param error [Exception] exception that was caught
    # @return [TrueClass]
    def _zoidberg_handle_unexpected_error(error)
      if(_raw_instance.respond_to?(:restart))
        unless(::Zoidberg.in_shutdown?)
          begin
            _raw_instance.restart(error)
            return # short circuit
          rescue => e
          end
        end
      end
      _zoidberg_destroy!
      if(@_supervised && !::Zoidberg.in_shutdown?)
        _aquire_lock!
        begin
          args = _build_args.dup
          inst = args.shift.unshelled_new(*args.first, &args.last)
          _zoidberg_set_instance(inst)
          ::Zoidberg.logger.debug "Supervised instance has been rebuilt: #{inst}"
          if(_raw_instance.respond_to?(:restarted!))
            _raw_instance.restarted!
          end
        ensure
          _release_lock!
        end
      end
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
        if(::Zoidberg.in_shutdown?)
          @_zoidberg_timer.terminate if @_zoidberg_timer
          @_zoidberg_signal.terminate if @_zoidberg_signal
        end
        if(_raw_instance.respond_to?(:terminate))
          begin
            if(_raw_instance.method(:terminate).arity == 0)
              _raw_instance.terminate
            else
              _raw_instance.terminate(error)
            end
          rescue => e
            ::Zoidberg.logger.error "Unexpected exception caught during terminatation of #{self}: #{e}"
            ::Zoidberg.logger.debug "#{e.class}: #{e}\n#{e.backtrace.join("\n")}"
          end
        end
        block.call if block
        oid = _raw_instance.object_id
        death_from_above = ::Proc.new do |*_|
          ::Kernel.raise ::Zoidberg::DeadException.new('Instance in terminated state!', oid)
        end
        death_from_above_display = ::Proc.new do
          "#<#{self.class.name}:TERMINATED>"
        end
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
      end
      true
    end

    def terminate
      _zoidberg_unsupervise
      _zoidberg_destroy!
    end
#    alias_method :terminate, :_zoidberg_destroy!

    # @return [self]
    def _zoidberg_object
      self
    end

    # Override to directly output object stringification
    def to_s
      _raw_instance.to_s
    end

    # Override to directly output object inspection
    def inspect
      _raw_instance.inspect
    end

    def signal(*args)
      _raw_instance.signal(*args)
    end

    def async(*args, &block)
      _raw_instance.async(*args, &block)
    end

    # Initialize the signal instance if not
    def _zoidberg_signal_interface
      unless(@_zoidberg_signal)
        @_zoidberg_signal = ::Zoidberg::Signal.new(:cache_signals => self.class.option?(:cache_signals))
      end
      @_zoidberg_signal
    end

    # @return [Timer]
    def _zoidberg_timer
      unless(@_zoidberg_timer)
        @_zoidberg_timer = Timer.new
      end
      @_zoidberg_timer
    end


  end
end

# jruby compat [https://github.com/jruby/jruby/pull/2520]
if(Zoidberg::Proxy.instance_methods.include?(:object_id))
  class Zoidberg::Proxy
    undef_method :object_id
  end
end
