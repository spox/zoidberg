require 'zoidberg'
require 'minitest/autorun'

Zoidberg.logger.level = ENV['DEBUG'] == 'true' ? 0 : 4
if(ENV['ZOIDBERG_SHELL'] == 'hard')
  Zoidberg.default_shell = Zoidberg::HardShell
end
ENV['ZOIDBERG_TESTING'] = 'true'
