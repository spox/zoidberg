require 'zoidberg'

Zoidberg.logger.level = ENV['DEBUG'] == 'true' ? 0 : 4
ENV['ZOIDBERG_TESTING'] = 'true'

Dir.glob(File.join(File.dirname(__FILE__), 'specs/*_spec.rb')).each do |path|
  require File.expand_path(path)
end
