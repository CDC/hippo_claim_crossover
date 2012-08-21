# -*- encoding: utf-8 -*-

Gem::Specification.new do |gem|
  gem.authors       = ["Jon Jackson"]
  gem.email         = ["jonj@promedicalinc.com"]
  gem.description   = %q{Map from HIPAA 837 claims to CMS 1500 pdfs.}
  gem.summary       = %q{Map from HIPAA 837 claims to CMS 1500 pdfs.}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "hippo_claim_crossover"
  gem.require_paths = ["lib"]
  gem.version       = "0.0.1"

  gem.add_dependency "hippo"
  gem.add_dependency "ruby_claim"
end
