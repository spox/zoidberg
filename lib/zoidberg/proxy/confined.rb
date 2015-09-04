require 'fiber'
require 'zoidberg'

module Zoidberg
  class Proxy
    class Confined < Proxy

      # @return [Thread] container thread
      attr_reader :_source_thread
      # @return [Queue] current request queue
      attr_reader :_requests
      # @return [TrueClass, FalseClass] blocked running task
      attr_reader :_blocked

      # Create a new isolation wrapper
      #
      # @param object [Object] object to wrap
      # @return [self]
      def initialize(klass, *args, &block)
        @_requests = ::Queue.new
        @_blocked = false
        @_source_thread = ::Thread.new do
          ::Zoidberg.logger.debug 'Starting the isolation request processor'
          ::Thread.current[:root_fiber] = ::Fiber.current
          _isolate!
        end
        @_build_args = [klass, *args, block]
        @_raw_instance = klass.unshelled_new(*args, &block)
        @_raw_instance._zoidberg_proxy(self)
        if(@_raw_instance.class.include?(::Zoidberg::Supervise))
          @_supervised = true
        end
        ::Zoidberg.logger.debug "Zoidberg object isolation wrap: #{@_build_args.inspect}"
      end

      # Call into instance asynchronously
      #
      # @note use caution with shared data using this method
      def _async_request(blocking, method_name, *args, &block)
        ::Zoidberg.logger.debug "Received async request from remote thread. Added to queue: #{_raw_instance.class}##{method_name}(#{args.map(&:inspect).join(', ')})"
        _requests << ::Smash.new(
          :uuid => ::Zoidberg.uuid,
          :arguments => [method_name, *args],
          :block => block,
          :response => nil,
          :async => true,
          :blocking => blocking == :blocking
        )
        nil
      end

      # Wrapping for provided object
      def method_missing(*args, &block)
        res = nil
        begin
          if(::ENV['ZOIDBERG_TESTING'])
            ::Kernel.require 'timeout'
            ::Timeout.timeout(::ENV.fetch('ZOIDBERG_TESTING_TIMEOUT', 5).to_i) do
              res = _isolated_request(*args, &block)
            end
          else
            res = _isolated_request(*args, &block)
          end
        rescue ::Zoidberg::Supervise::AbortException => e
          ::Kernel.raise e.original_exception
        rescue ::Exception => e
          _zoidberg_unexpected_error(e)
          ::Zoidberg.logger.debug "Exception on: #{_raw_instance.class}##{args.first}(#{args.slice(1, args.size).map(&:inspect).join(', ')})"
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
          unless(_source_thread.alive?)
            ::Kernel.raise ::Zoidberg::DeadException.new('Instance in terminated state!')
          end
          ::Zoidberg.logger.debug "Received request from remote thread. Added to queue: #{_raw_instance.class}##{method_name}(#{args.map(&:inspect).join(', ')})"
          response_queue = ::Queue.new
          _requests << ::Smash.new(
            :uuid => ::Zoidberg.uuid,
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

      def _zoidberg_available?
        !_blocked
      end

      protected

      # Process requests
      def _isolate!
        begin
          ::Kernel.loop do
            begin
              _process_request(_requests.pop)
            rescue => e
              ::Zoidberg.logger.error "Unexpected looping error! (#{e.class}: #{e})"
              ::Zoidberg.logger.error "#{e.class}: #{e}\n#{e.backtrace.join("\n")}"
              ::Thread.main.raise e
            end
          end
        ensure
          until(_requests.empty)
            requests.pop[:response] << ::Zoidberg::DeadException.new('Instance in terminated state!')
          end
        end
      end

      # Process a request
      #
      # @param request [Hash]
      # @return [self]
      def _process_request(request)
        begin
          @_blocked = !request[:async]
          ::Zoidberg.logger.debug "Processing received request: #{request.inspect}"
          unless(request[:task])
            request[:task] = ::Zoidberg::Task.new(request[:async] ? :async : :serial, _raw_instance, [request]) do |req|
              begin
                result = origin.__send__(
                  *req[:arguments],
                  &req[:block]
                )
                if(req[:response])
                  req[:response] << result
                end
              rescue ::Exception => exception
                if(req[:response])
                  req[:response] << exception
                end
              end
            end
          end
          if(request[:task].waiting?)
            if(_raw_instance.alive?)
              request[:task].proceed
              request[:task].value if request[:blocking]
            else
              request[:response] << ::Zoidberg::DeadException.new('Instance in terminated state!')
              request[:task].halt!
            end
          end
          _requests.push(request) unless request[:task].complete? || request[:async]
          ::Zoidberg.logger.debug "Request processing completed. #{request.inspect}"
        ensure
          @_blocked = false
        end
        self
      end

    end

  end
end
