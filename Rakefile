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

desc "Build CLI binaries"
task :build_binaries do
  Dir.chdir("ext/phrasekit") do
    sh "cargo build --release --bins"
  end
end

task compile: :build_binaries

task default: [:compile, :spec]
