require 'zoidberg'

module Zoidberg
  class Proxy
    class Confined < Proxy

      # @return [Thread] container thread
      attr_reader :_source_thread
      # @return [Queue] current request queue
      attr_reader :_requests

      # Create a new isolation wrapper
      #
      # @param object [Object] object to wrap
      # @return [self]
      def initialize(klass, *args, &block)
        @_build_args = [klass, *args, block]
        @_raw_instance = klass.unshelled_new(*args, &block)
        @_raw_instance._zoidberg_proxy(self)
        if(@_raw_instance.class.include?(::Zoidberg::Supervise))
          @_supervised = true
        end
        @_requests = ::Queue.new
        @_source_thread = ::Thread.new do
          ::Zoidberg.logger.debug 'Starting the isolation request processor'
          ::Thread.current[:root_fiber] = ::Fiber.current
          _isolate!
        end
        ::Zoidberg.logger.debug "Zoidberg object isolation wrap: #{@_build_args.inspect}"
      end

      # Call into instance asynchronously
      #
      # @note use caution with share data using this method
      def async(method_name, *args, &block)
        ::Zoidberg.logger.debug "Received async request from remote thread. Added to queue: #{_raw_instance.class}##{method_name}(#{args.map(&:inspect).join(', ')})"
        _requests << ::Smash.new(
          :uuid => ::SecureRandom.uuid,
          :arguments => [method_name, *args],
          :block => block,
          :response => nil,
          :async => true
        )
        nil
      end

      # Wrapping for provided object
      def method_missing(*args, &block)
        res = nil
        begin
          if(::ENV['ZOIDBERG_TESTING'])
            ::Kernel.require 'timeout'
            ::Timeout.timeout(20) do
              res = _isolated_request(*args, &block)
            end
          else
            res = _isolated_request(*args, &block)
          end
        rescue ::Zoidberg::Supervise::AbortException => e
          ::Kernel.raise e.original_exception
        rescue ::Exception => e
          ::Zoidberg.logger.error "Unexpected exception: #{e.class} - #{e}"
          if((defined?(Timeout) && e.is_a?(Timeout::Error)) || e.is_a?(::Zoidberg::DeadException))
            ::Kernel.raise e
          end
          if(_zoidberg_link)
            if(_zoidberg_link.class.trap_exit)
              ::Zoidberg.logger.warn "Calling linked exit trapper #{_raw_instance.class} -> #{_zoidberg_link.class}: #{e.class} - #{e}"
              _zoidberg_link.async.send(
                _zoidberg_link.class.trap_exit, _raw_instance, e
              )
            end
          else
            if(@_supervised)
              ::Zoidberg.logger.warn "Unexpected error for supervised class `#{_raw_instance.class}`. Handling error (#{e.class} - #{e})"
              _zoidberg_handle_unexpected_error(e)
            end
          end
          ::Kernel.raise e
        end
        res
      end

      # Send the method request to the wrapped instance
      #
      # @param method_name [String, Symbol] method to call on instance
      # @param args [Object] arguments for call
      # @yield block for call
      # @return [Object] result
      def _isolated_request(method_name, *args, &block)
        if(_source_thread == ::Thread.current)
          ::Zoidberg.logger.debug "Received request from source thread: #{_raw_instance.class}##{method_name}(#{args.map(&:inspect).join(', ')})"
          _raw_instance.__send__(method_name, *args, &block)
        else
          ::Zoidberg.logger.debug "Received request from remote thread. Added to queue: #{_raw_instance.class}##{method_name}(#{args.map(&:inspect).join(', ')})"
          response_queue = ::Queue.new
          _requests << ::Smash.new(
            :uuid => ::SecureRandom.uuid,
            :arguments => [method_name, *args],
            :block => block,
            :response => response_queue
          )
          result = response_queue.pop
          if(result.is_a?(::Exception))
            ::Kernel.raise result
          else
            result
          end
        end
      end

      protected

      # Process requests
      def _isolate!
        ::Kernel.loop do
          begin
            _process_request(_requests.pop)
          rescue => e
            # TODO: bubble error and allow teardown/restore if supervised
            ::Zoidberg.logger.error "Unexpected looping error! (#{e.class}: #{e})"
            ::Zoidberg.logger.error "#{e.class}: #{e}\n#{e.backtrace.join("\n")}"
          end
        end
      end

      # Process a request
      #
      # @param request [Hash]
      # @return [self]
      def _process_request(request)
        ::Zoidberg.logger.debug "Processing received request: #{request.inspect}"
        unless(request[:task])
          request[:task] = ::Zoidberg::Task.new(request[:async] ? :async : :serial, _raw_instance, [request]) do |req|
            begin
              result << origin.__send__(
                *req[:arguments],
                &req[:block]
              )
              if(req[:response])
                req[:response] << result
              end
            rescue ::Exception => exception
              if(req[:response])
                req[:response] << exception
              else
                ::Kernel.raise exception
              end
            end
          end
        end
        if(request[:task].waiting?)
          request[:task].proceed
        end
        _requests.push(request) unless request[:task].complete?
        ::Zoidberg.logger.debug "Request processing completed. #{request.inspect}"
        self
      end

    end

  end
end
