require "bundler/gem_tasks"
require "rake/extensiontask"

# rspec is a dev dependency. The rb-sys-dock cross-build container installs the
# RUNTIME bundle only, so this require is absent there — guard it so the Rakefile
# still loads (and `native:<platform>` stays reachable) in a build-only container.
begin
  require "rspec/core/rake_task"
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
  desc "spec (rspec unavailable here)"
  task(:spec) { abort "rspec is a dev dependency" }
end

# Pass the gemspec so rake-compiler defines the native:<platform> gem tasks that
# rb-sys-dock invokes for each precompiled leg (without it the cross build fails
# with "Don't know how to build task native:<platform>").
GEMSPEC = Gem::Specification.load("phrasekit.gemspec")

Rake::ExtensionTask.new("phrasekit", GEMSPEC) do |ext|
  ext.lib_dir = "lib/phrasekit"
  ext.ext_dir = "ext/phrasekit"
  ext.cross_compile = true
  ext.cross_platform = ["x86_64-linux", "aarch64-linux", "x86_64-darwin", "arm64-darwin"]
end

task default: [:compile, :spec]
