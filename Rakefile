require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rake/extensiontask"

RSpec::Core::RakeTask.new(:spec)

Rake::ExtensionTask.new("phrasekit") do |ext|
  ext.lib_dir = "lib/phrasekit"
  ext.ext_dir = "ext/phrasekit"
  ext.cross_compile = true
  ext.cross_platform = ["x86_64-linux", "x86_64-darwin", "arm64-darwin"]
end

task default: [:compile, :spec]
