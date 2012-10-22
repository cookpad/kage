# -*- encoding: utf-8 -*-
require File.expand_path('../lib/kage/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Tatsuhiko Miyagawa"]
  gem.email         = ["miyagawa@bulknews.net"]
  gem.description   = %q{em-proxy based shadow proxy server}
  gem.summary       = %q{Kage (kah-geh) is an HTTP shadow proxy server that sits between your production servers to send shaddow traffic to the servers with new code changes.}
  gem.homepage      = "https://github.com/cookpad/kage"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "kage"
  gem.require_paths = ["lib"]
  gem.version       = Kage::VERSION

  gem.add_dependency 'em-proxy', '>= 0.1.7'
  gem.add_dependency 'http_parser.rb', '>= 0.5.3'

  gem.add_development_dependency 'rspec'
end
