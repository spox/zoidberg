$LOAD_PATH.unshift File.expand_path(File.dirname(__FILE__)) + '/lib/'
require 'zoidberg/version'
Gem::Specification.new do |s|
  s.name = 'zoidberg'
  s.version = Zoidberg::VERSION.version
  s.summary = 'Why not?'
  s.author = 'Chris Roberts'
  s.email = 'code@chrisroberts.org'
  s.homepage = 'https://github.com/spox/zoidberg'
  s.description = 'Friends!'
  s.require_path = 'lib'
  s.license = 'Apache 2.0'
  s.add_runtime_dependency 'bogo'
  s.add_runtime_dependency 'concurrent-ruby', '~> 1.0.0'
  s.add_runtime_dependency 'concurrent-ruby-edge', '~> 0.2.0'
  s.add_runtime_dependency 'mono_logger'
  s.add_development_dependency 'pry'
  s.add_development_dependency 'minitest'
  s.files = Dir['lib/**/*'] + %w(zoidberg.gemspec README.md CHANGELOG.md CONTRIBUTING.md LICENSE)
end
