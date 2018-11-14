Gem::Specification.new do |spec|
  spec.name          = "fluent-plugin-splunk-hec"
  spec.version       = File.read("VERSION")
  spec.authors       = ["Zhimin (Gimi) Liang"]
  spec.email         = ["zliang@splunk.com"]

  spec.summary       = %q{Fluentd plugin for Splunk HEC.}
  spec.description   = %q{A fluentd output plugin created by Splunk that writes events to splunk indexers over HTTP Event Collector API.}
  spec.homepage      = "https://github.com/splunk/fluent-plugin-splunk-hec"
  spec.license       = "Apache-2.0"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  # if spec.respond_to?(:metadata)
  #   spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"
  # else
  #   raise "RubyGems 2.0 or newer is required to protect against " \
  #     "public gem pushes."
  # end

  spec.require_paths = ["lib"]
  spec.test_files    = Dir.glob('test/**/**.rb')
  spec.files         = %w[
    CODE_OF_CONDUCT.md README.md LICENSE
    fluent-plugin-splunk-hec.gemspec
    Gemfile Gemfile.lock
    Rakefile VERSION
  ] + Dir.glob('lib/**/**').reject(&File.method(:directory?))

  spec.required_ruby_version = '>= 2.4.0'

  spec.add_runtime_dependency "fluentd", "~> 1.0"
  spec.add_runtime_dependency "multi_json", "~> 1.13"
  spec.add_runtime_dependency "net-http-persistent", "~> 3.0"

  spec.add_development_dependency "bundler", "~> 1.16"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "test-unit", "~> 3.0" # required by fluent/test.rb
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "webmock", "~> 3.4.2"
  spec.add_development_dependency "simplecov", "~> 0.16.1"
end
