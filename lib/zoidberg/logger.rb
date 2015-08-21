require 'zoidberg'
require 'mono_logger'

module Zoidberg
  # Logger
  class Logger < MonoLogger

    # Quick override to ensure destination has append mode enabled if
    # file io type
    def initialize(logdev, *args)
      if(logdev.respond_to?(:path))
        begin
          require 'fcntl'
          unless(logdev.fcntl(Fcntl::F_GETFL) & Fcntl::O_APPEND == Fcntl::O_APPEND)
            logdev = File.open(logdev.path, (File::WRONLY | File::APPEND))
          end
        rescue; end
      end
      super(logdev, *args)
    end

  end
end
