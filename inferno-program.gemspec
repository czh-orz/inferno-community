# coding: utf-8
lib = File.expand_path('./lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'version'

Gem::Specification.new do |spec|
  spec.name          = 'inferno-program'
  spec.version       = Inferno::VERSION
  spec.authors       = ['Rob Scanlon', 'Reece Adamson', 'Chase Zhou']
  spec.email         = ['rscanlon@mitre.org']

  spec.summary       = %q{Inferno Smart Launch}
  spec.description   = %q{Inferno Smart Launch}
  spec.homepage      = 'https://github.com/siteadmin/inferno'

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'inferno-smart-launch'
end
