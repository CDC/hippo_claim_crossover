# -*- encoding: utf-8 -*-
require File.expand_path('../lib/hippo_claim_crossover/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Jon Jackson"]
  gem.email         = ["jonj@promedicalinc.com"]
  gem.description   = %q{TODO: Write a gem description}
  gem.summary       = %q{TODO: Write a gem summary}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "hippo_claim_crossover"
  gem.require_paths = ["lib"]
  gem.version       = HippoClaimCrossover::VERSION

  gem.dependency "hippo"
  gem.dependency "ruby_claim"
end
