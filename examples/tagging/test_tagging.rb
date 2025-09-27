#!/usr/bin/env ruby

require "bundler/setup"
require "phrasekit"
require "json"

puts "Testing PhraseKit::Tagger"
puts "=" * 50

script_dir = File.dirname(__FILE__)

puts "\n1. First, we need to build matcher artifacts..."
puts "   Using phrases from scoring example"

phrases_path = File.join(script_dir, "../scoring/phrases.jsonl")
unless File.exist?(phrases_path)
  puts "   ❌ No phrases found. Run scoring example first:"
  puts "      cd examples/scoring && bundle exec ruby test_scoring.rb"
  exit 1
end

output_dir = File.join(script_dir, "output")
Dir.mkdir(output_dir) unless Dir.exist?(output_dir)

build_config = {
  automaton_path: File.join(output_dir, "phrases.daac"),
  payloads_path: File.join(output_dir, "payloads.bin"),
  manifest_path: File.join(output_dir, "manifest.json"),
  vocab_path: File.join(output_dir, "vocab.json"),
  tokenizer: "whitespace",
  version: "test-v1",
  separator_id: 4294967294
}

config_path = File.join(output_dir, "build_config.json")
File.write(config_path, JSON.generate(build_config))

build_cmd = [
  File.join(script_dir, "../../ext/phrasekit/target/release/phrasekit_build"),
  phrases_path,
  config_path,
  output_dir
]

puts "   Building artifacts..."
system(build_cmd.shelljoin, exception: true)

puts "\n2. Tagging corpus..."
stats = PhraseKit::Tagger.tag(
  input_path: File.join(script_dir, "corpus.jsonl"),
  output_path: File.join(output_dir, "tagged_corpus.jsonl"),
  artifacts_dir: output_dir,
  policy: :leftmost_longest,
  max_spans: 100
)

puts "   ✓ Tagging complete!"
puts "   Statistics:"
stats.each do |key, value|
  puts "     #{key}: #{value}"
end

puts "\n3. Sample tagged documents:"
tagged_docs = File.readlines(File.join(output_dir, "tagged_corpus.jsonl"))
  .map { |line| JSON.parse(line) }
  .select { |doc| doc["spans"].any? }
  .take(3)

tagged_docs.each do |doc|
  puts "\n   Document: #{doc["doc_id"]}"
  puts "   Tokens: #{doc["tokens"].join(" ")}"
  puts "   Spans:"
  doc["spans"].each do |span|
    phrase_tokens = doc["tokens"][span["start"]...span["end"]]
    puts "     - [#{span["start"]}:#{span["end"]}] \"#{phrase_tokens.join(" ")}\" (phrase_id=#{span["phrase_id"]}, label=#{span["label"]})"
  end
end

puts "\n✅ Test complete!"