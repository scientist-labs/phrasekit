#!/usr/bin/env ruby

require "bundler/setup"
require "phrasekit"
require "json"

puts "Testing PhraseKit::Scorer"
puts "=" * 50

# Use paths relative to this script
script_dir = File.dirname(__FILE__)

# Score phrases
puts "\n1. Scoring domain phrases against background..."
stats = PhraseKit::Scorer.score(
  domain_path: File.join(script_dir, "domain_phrases.jsonl"),
  background_path: File.join(script_dir, "background_phrases.jsonl"),
  output_path: File.join(script_dir, "phrases_ruby.jsonl"),
  method: :ratio,
  min_salience: 2.0,
  min_domain_count: 2
)

puts "   ✓ Scoring complete!"
puts "   Statistics:"
stats.each do |key, value|
  puts "     #{key}: #{value}"
end

# Load and display top phrases
puts "\n2. Top phrases by salience:"
phrases = File.readlines(File.join(script_dir, "phrases_ruby.jsonl"))
  .map { |line| JSON.parse(line) }
  .sort_by { |p| -p["salience"] }
  .take(10)

phrases.each_with_index do |phrase, i|
  puts "   #{i + 1}. #{phrase["tokens"].join(" ")} → salience=#{phrase["salience"].round(2)}, phrase_id=#{phrase["phrase_id"]}"
  puts "      (domain=#{phrase["domain_count"]}, background=#{phrase["background_count"]})"
end

# Test different methods
puts "\n3. Testing different scoring methods..."

[:ratio, :pmi, :tfidf].each do |method|
  stats = PhraseKit::Scorer.score(
    domain_path: File.join(script_dir, "domain_phrases.jsonl"),
    background_path: File.join(script_dir, "background_phrases.jsonl"),
    output_path: File.join(script_dir, "phrases_#{method}.jsonl"),
    method: method,
    min_salience: 1.0,  # Lower threshold to see differences
    min_domain_count: 2
  )

  phrase_count = stats[:after_salience_filter]
  puts "   #{method}: #{phrase_count} phrases passed filter"
end

puts "\n✅ Test complete!"