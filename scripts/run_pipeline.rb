#!/usr/bin/env ruby

require "bundler/setup"
require "phrasekit"
require "json"
require "fileutils"

corpus_path = ARGV[0]
output_dir = ARGV[1] || "phrasekit_output"
background_path = ARGV[2] || "background_phrases.jsonl"

if corpus_path.nil? || !File.exist?(corpus_path)
  puts "Usage: ruby scripts/run_pipeline.rb <corpus.jsonl> [output_dir] [background.jsonl]"
  puts
  puts "Example:"
  puts "  ruby scripts/run_pipeline.rb corpus.jsonl output/ background.jsonl"
  puts
  puts "Note: You need a background corpus. Options:"
  puts "  1. Use a pre-built one (Wikipedia, news, etc.)"
  puts "  2. Create a simple one with common phrases"
  puts "  3. See docs/REAL_WORLD_USAGE.md for details"
  exit 1
end

if !File.exist?(background_path)
  puts "⚠️  Background corpus not found: #{background_path}"
  puts
  puts "Creating minimal background corpus..."

  # Create minimal background corpus for testing
  common_ngrams = {
    ["for", "the"] => 50000,
    ["in", "the"] => 45000,
    ["to", "the"] => 30000,
    ["of", "the"] => 60000,
    ["and", "the"] => 25000,
    ["with", "a"] => 20000,
    ["from", "the"] => 18000,
    ["at", "the"] => 15000,
    ["on", "the"] => 12000,
    ["is", "a"] => 20000,
    ["it", "is"] => 15000,
    ["this", "is"] => 12000,
    ["can", "be"] => 10000,
    ["will", "be"] => 9000,
    ["has", "been"] => 8000
  }

  File.open(background_path, "w") do |f|
    common_ngrams.each do |tokens, count|
      f.puts JSON.generate({tokens: tokens, count: count})
    end
  end

  puts "✓ Created minimal background corpus: #{background_path}"
  puts "  (For better results, use a real background corpus)"
  puts
end

FileUtils.mkdir_p(output_dir)

puts "=" * 70
puts "PhraseKit Real Data Pipeline"
puts "=" * 70
puts "Corpus:     #{corpus_path}"
puts "Output:     #{output_dir}"
puts "Background: #{background_path}"
puts

# Validate corpus
puts "Validating corpus..."
line_count = `wc -l < #{corpus_path}`.to_i
file_size_mb = File.size(corpus_path) / 1_048_576.0
puts "  Documents: #{line_count}"
puts "  File size: #{file_size_mb.round(2)} MB"
puts

# Auto-tune parameters based on corpus size
min_count = case line_count
when 0..1_000 then 2
when 1_001..10_000 then 5
when 10_001..100_000 then 10
when 100_001..1_000_000 then 20
else 50
end

min_domain_count = [min_count, 10].max

puts "Auto-tuned parameters:"
puts "  min_count: #{min_count} (mining threshold)"
puts "  min_domain_count: #{min_domain_count} (scoring threshold)"
puts

# Step 1: Mine n-grams
puts "STEP 1: Mining n-grams (10-50K docs/sec)..."
puts "-" * 70
start_time = Time.now
candidate_phrases_path = File.join(output_dir, "candidate_phrases.jsonl")

stats = PhraseKit::Miner.mine(
  input_path: corpus_path,
  output_path: candidate_phrases_path,
  min_n: 2,
  max_n: 5,
  min_count: min_count
)

mining_time = Time.now - start_time
throughput = (line_count / mining_time).round(0)
puts "  ✓ Completed in #{mining_time.round(2)}s"
puts "  ✓ Unique n-grams: #{stats[:unique_ngrams]}"
puts "  ✓ After filtering: #{stats[:ngrams_after_filter]}"
puts "  ✓ Throughput: #{throughput} docs/sec"
puts

# Step 2: Score phrases
puts "STEP 2: Scoring by salience (100K phrases/sec)..."
puts "-" * 70
start_time = Time.now
phrases_path = File.join(output_dir, "phrases.jsonl")

score_stats = PhraseKit::Scorer.score(
  domain_path: candidate_phrases_path,
  background_path: background_path,
  output_path: phrases_path,
  method: :ratio,
  min_salience: 2.0,
  min_domain_count: min_domain_count
)

scoring_time = Time.now - start_time
puts "  ✓ Completed in #{scoring_time.round(2)}s"
puts "  ✓ Domain phrases: #{score_stats[:domain_phrases]}"
puts "  ✓ Background phrases: #{score_stats[:background_phrases]}"
puts "  ✓ High-salience phrases: #{score_stats[:after_salience_filter]}"
puts

if score_stats[:after_salience_filter] == 0
  puts "⚠️  WARNING: No phrases passed salience filter!"
  puts "   Try:"
  puts "   - Lower min_salience (currently 2.0)"
  puts "   - Better background corpus"
  puts "   - Check your data quality"
  puts
end

# Step 3: Build matcher
puts "STEP 3: Building matcher artifacts..."
puts "-" * 70
start_time = Time.now
artifacts_dir = File.join(output_dir, "artifacts")
FileUtils.mkdir_p(artifacts_dir)

build_config = {
  version: "production-v1",
  tokenizer: "whitespace",
  separator_id: 4294967294
}
config_path = File.join(output_dir, "build_config.json")
File.write(config_path, JSON.generate(build_config))

build_binary = File.expand_path("../ext/phrasekit/target/release/phrasekit_build", __dir__)

if !File.exist?(build_binary)
  puts "⚠️  Build binary not found. Compiling..."
  system("cargo build --release --bin phrasekit_build --manifest-path ext/phrasekit/Cargo.toml")
end

build_cmd = [build_binary, phrases_path, config_path, artifacts_dir]
system(build_cmd.shelljoin, out: File::NULL, err: File::NULL)

building_time = Time.now - start_time
puts "  ✓ Completed in #{building_time.round(2)}s"
puts "  ✓ Artifacts: #{artifacts_dir}/"
puts

# Step 4: Tag corpus
puts "STEP 4: Tagging corpus with phrases (50-100K docs/sec)..."
puts "-" * 70
start_time = Time.now
tagged_corpus_path = File.join(output_dir, "tagged_corpus.jsonl")

tag_stats = PhraseKit::Tagger.tag(
  input_path: corpus_path,
  output_path: tagged_corpus_path,
  artifacts_dir: artifacts_dir,
  policy: :leftmost_longest,
  max_spans: 100
)

tagging_time = Time.now - start_time
throughput = (line_count / tagging_time).round(0)
coverage = ((tag_stats[:docs_with_spans].to_f / tag_stats[:documents]) * 100).round(2)

puts "  ✓ Completed in #{tagging_time.round(2)}s"
puts "  ✓ Documents tagged: #{tag_stats[:documents]}"
puts "  ✓ Total spans: #{tag_stats[:total_spans]}"
puts "  ✓ Coverage: #{coverage}%"
puts "  ✓ Throughput: #{throughput} docs/sec"
puts

if coverage < 10
  puts "⚠️  WARNING: Low span coverage (#{coverage}%)"
  puts "   Your phrases may be too specific."
  puts "   Try: lower min_count or min_salience"
  puts
end

# Summary
total_time = mining_time + scoring_time + building_time + tagging_time
puts "=" * 70
puts "Pipeline complete!"
puts "=" * 70
puts "Total time: #{total_time.round(2)}s (#{(total_time / 60).round(2)} minutes)"
puts
puts "Outputs:"
puts "  • #{candidate_phrases_path}"
puts "  • #{phrases_path}"
puts "  • #{tagged_corpus_path}"
puts "  • #{artifacts_dir}/"
puts

# Quick stats
puts "Summary Statistics:"
puts "  • Phrase candidates: #{stats[:ngrams_after_filter]}"
puts "  • High-value phrases: #{score_stats[:after_salience_filter]}"
puts "  • Span coverage: #{coverage}%"
puts "  • Avg spans/doc: #{tag_stats[:avg_spans_per_doc].round(2)}"
puts

# Top phrases
if File.exist?(phrases_path) && File.size(phrases_path) > 0
  puts "Top 20 phrases by salience:"
  puts "-" * 70

  top_phrases = File.readlines(phrases_path)
    .map { |line| JSON.parse(line) }
    .sort_by { |p| -p["salience"] }
    .take(20)

  top_phrases.each_with_index do |phrase, i|
    text = phrase["tokens"].join(" ")
    salience = phrase["salience"].round(2)
    count = phrase["domain_count"]
    puts "  #{(i + 1).to_s.rjust(2)}. #{text.ljust(40)} salience=#{salience.to_s.rjust(6)} count=#{count}"
  end
  puts
end

# Sample tagged documents
if File.exist?(tagged_corpus_path) && File.size(tagged_corpus_path) > 0
  puts "Sample tagged documents:"
  puts "-" * 70

  tagged_docs = File.readlines(tagged_corpus_path)
    .map { |line| JSON.parse(line) }
    .select { |doc| doc["spans"].any? }
    .take(5)

  tagged_docs.each do |doc|
    puts
    puts "  Document: #{doc["doc_id"]}"
    puts "  Tokens: #{doc["tokens"][0..20].join(" ")}#{doc["tokens"].size > 20 ? '...' : ''}"
    puts "  Spans:"
    doc["spans"].each do |span|
      phrase_text = doc["tokens"][span["start"]...span["end"]].join(" ")
      puts "    → [#{span["start"]}:#{span["end"]}] \"#{phrase_text}\" (id=#{span["phrase_id"]})"
    end
  end
  puts
end

puts "Next steps:"
puts "  • Review top phrases above"
puts "  • Adjust parameters if needed"
puts "  • Export to NER format (coming soon!)"
puts "  • Use artifacts/ for production matching"
puts