require_relative "lib/phrasekit/version"

Gem::Specification.new do |spec|
  spec.name = "phrasekit"
  spec.version = PhraseKit::VERSION
  spec.authors = ["PhraseKit Contributors"]
  spec.email = [""]

  spec.summary = "Ultra-fast deterministic phrase matcher"
  spec.description = "High-performance phrase matching using Aho-Corasick automaton with Ruby bindings via Magnus"
  spec.homepage = "https://github.com/scientist-labs/phrasekit"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"
  spec.required_rubygems_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*.rb", "ext/**/*.{rs,rb,toml}", "Cargo.*", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]
  spec.extensions = ["ext/phrasekit/extconf.rb"]

  spec.add_dependency "rb_sys", "~> 0.9"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rake-compiler", "~> 1.2"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "spellkit", "~> 0.1.1"
end
