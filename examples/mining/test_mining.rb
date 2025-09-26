#!/usr/bin/env ruby

require "bundler/setup"
require "phrasekit"
require "json"

puts "Testing PhraseKit::Miner"
puts "=" * 50

# Use paths relative to this script
script_dir = File.dirname(__FILE__)

# Mine n-grams from corpus
puts "\n1. Mining n-grams from corpus..."
stats = PhraseKit::Miner.mine(
  input_path: File.join(script_dir, "corpus.jsonl"),
  output_path: File.join(script_dir, "candidate_phrases_ruby.jsonl"),
  min_n: 2,
  max_n: 5,
  min_count: 2
)

puts "   ✓ Mining complete!"
puts "   Statistics:"
stats.each do |key, value|
  puts "     #{key}: #{value}"
end

# Load and display top n-grams
puts "\n2. Top n-grams by frequency:"
ngrams = File.readlines(File.join(script_dir, "candidate_phrases_ruby.jsonl"))
  .map { |line| JSON.parse(line) }
  .sort_by { |ng| -ng["count"] }
  .take(10)

ngrams.each_with_index do |ng, i|
  puts "   #{i + 1}. #{ng["tokens"].join(" ")} → #{ng["count"]} occurrences"
end

puts "\n✅ Test complete!"