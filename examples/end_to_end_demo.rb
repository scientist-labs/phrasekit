#!/usr/bin/env ruby

require "bundler/setup"
require "phrasekit"
require "json"
require "fileutils"

puts "=" * 70
puts "PhraseKit End-to-End Demo"
puts "Weak Supervision Pipeline for NER"
puts "=" * 70
puts

script_dir = File.dirname(__FILE__)
work_dir = File.join(script_dir, "demo_output")
FileUtils.mkdir_p(work_dir)

puts "📁 Working directory: #{work_dir}"
puts

corpus_path = File.join(work_dir, "corpus.jsonl")
File.open(corpus_path, "w") do |f|
  f.puts('{"doc_id":"doc_1","tokens":["the","rat","cdk10","oligo","was","used","in","the","experiment"]}')
  f.puts('{"doc_id":"doc_2","tokens":["add","protein","assay","buffer","to","the","sample"]}')
  f.puts('{"doc_id":"doc_3","tokens":["prepare","lysis","buffer","according","to","protocol"]}')
  f.puts('{"doc_id":"doc_4","tokens":["western","blot","analysis","was","performed"]}')
  f.puts('{"doc_id":"doc_5","tokens":["the","master","mix","contains","rat","cdk10","oligo"]}')
  f.puts('{"doc_id":"doc_6","tokens":["protein","assay","buffer","preparation","is","critical"]}')
  f.puts('{"doc_id":"doc_7","tokens":["rat","cdk10","protein","expression","levels"]}')
  f.puts('{"doc_id":"doc_8","tokens":["for","the","western","blot","procedure"]}')
  f.puts('{"doc_id":"doc_9","tokens":["master","mix","preparation","guidelines"]}')
  f.puts('{"doc_id":"doc_10","tokens":["in","the","lysis","buffer","add","reagent"]}')
end

background_path = File.join(work_dir, "background_phrases.jsonl")
File.open(background_path, "w") do |f|
  f.puts('{"tokens":["for","the"],"count":50000}')
  f.puts('{"tokens":["in","the"],"count":30000}')
  f.puts('{"tokens":["to","the"],"count":25000}')
  f.puts('{"tokens":["lysis","buffer"],"count":8}')
  f.puts('{"tokens":["western","blot"],"count":5}')
end

puts "📚 STEP 1: Mining N-grams from Corpus"
puts "-" * 70
candidate_phrases_path = File.join(work_dir, "candidate_phrases.jsonl")
mine_stats = PhraseKit::Miner.mine(
  input_path: corpus_path,
  output_path: candidate_phrases_path,
  min_n: 2,
  max_n: 5,
  min_count: 2
)

puts "   ✓ Mined #{mine_stats[:unique_ngrams]} unique n-grams"
puts "   ✓ After min_count filter: #{mine_stats[:ngrams_after_filter]} phrases"
puts

puts "📊 STEP 2: Scoring Phrases by Salience"
puts "-" * 70
phrases_path = File.join(work_dir, "phrases.jsonl")
score_stats = PhraseKit::Scorer.score(
  domain_path: candidate_phrases_path,
  background_path: background_path,
  output_path: phrases_path,
  method: :ratio,
  min_salience: 2.0,
  min_domain_count: 2
)

puts "   ✓ Scored #{score_stats[:domain_phrases]} domain phrases"
puts "   ✓ Against #{score_stats[:background_phrases]} background phrases"
puts "   ✓ High-salience phrases: #{score_stats[:after_salience_filter]}"
puts

puts "🔧 STEP 3: Building Matcher Artifacts"
puts "-" * 70
artifacts_dir = File.join(work_dir, "artifacts")
FileUtils.mkdir_p(artifacts_dir)

build_config_path = File.join(work_dir, "build_config.json")
File.write(build_config_path, JSON.generate({
  version: "demo-v1",
  tokenizer: "whitespace",
  separator_id: 4294967294
}))

build_cmd = [
  File.join(script_dir, "../ext/phrasekit/target/release/phrasekit_build"),
  phrases_path,
  build_config_path,
  artifacts_dir
]

puts "   Building..."
system(build_cmd.shelljoin, out: File::NULL, err: File::NULL)
puts "   ✓ Created matcher artifacts"
puts

puts "🏷️  STEP 4: Tagging Corpus with Phrases"
puts "-" * 70
tagged_corpus_path = File.join(work_dir, "tagged_corpus.jsonl")
tag_stats = PhraseKit::Tagger.tag(
  input_path: corpus_path,
  output_path: tagged_corpus_path,
  artifacts_dir: artifacts_dir,
  policy: :leftmost_longest,
  max_spans: 100
)

puts "   ✓ Tagged #{tag_stats[:documents]} documents"
puts "   ✓ Found #{tag_stats[:total_spans]} total phrase spans"
puts "   ✓ Documents with matches: #{tag_stats[:docs_with_spans]}"
puts "   ✓ Avg spans per document: #{'%.2f' % tag_stats[:avg_spans_per_doc]}"
puts

puts "🎯 STEP 5: Loading Matcher for Interactive Use"
puts "-" * 70
PhraseKit.load!(
  automaton_path: File.join(artifacts_dir, "phrases.daac"),
  payloads_path: File.join(artifacts_dir, "payloads.bin"),
  manifest_path: File.join(artifacts_dir, "manifest.json"),
  vocab_path: File.join(artifacts_dir, "vocab.json")
)

stats = PhraseKit.stats
puts "   ✓ Loaded matcher"
puts "   ✓ Version: #{stats[:version]}"
puts "   ✓ Patterns: #{stats[:num_patterns]}"
puts "   ✓ Memory: #{'%.2f' % stats[:heap_mb]} MB"
puts

puts "🔍 STEP 6: Interactive Matching Demo"
puts "-" * 70

test_sequences = [
  ["rat", "cdk10", "oligo"],
  ["protein", "assay", "buffer"],
  ["western", "blot", "analysis"],
  ["for", "the", "experiment"]
]

test_sequences.each do |tokens|
  matches = PhraseKit.match_text_tokens(tokens: tokens)
  if matches.any?
    match = matches.first
    matched_text = tokens[match[:start]...match[:end]].join(" ")
    puts "   ✓ \"#{tokens.join(" ")}\" → MATCH: \"#{matched_text}\" (phrase_id=#{match[:phrase_id]})"
  else
    puts "   ✗ \"#{tokens.join(" ")}\" → no match"
  end
end
puts

puts "📄 STEP 7: Sample Tagged Documents"
puts "-" * 70

tagged_docs = File.readlines(tagged_corpus_path)
  .map { |line| JSON.parse(line) }
  .select { |doc| doc["spans"].any? }
  .take(3)

tagged_docs.each_with_index do |doc, i|
  puts "\n   Document #{i + 1}: #{doc["doc_id"]}"
  puts "   Tokens: #{doc["tokens"].join(" ")}"
  puts "   Spans:"
  doc["spans"].each do |span|
    phrase_tokens = doc["tokens"][span["start"]...span["end"]]
    puts "     → [#{span["start"]}:#{span["end"]}] \"#{phrase_tokens.join(" ")}\" (phrase_id=#{span["phrase_id"]})"
  end
end
puts

puts "=" * 70
puts "✅ Demo Complete!"
puts "=" * 70
puts
puts "📂 All outputs saved to: #{work_dir}"
puts
puts "Generated files:"
puts "  • corpus.jsonl              - Original corpus (10 documents)"
puts "  • candidate_phrases.jsonl   - Mined n-grams"
puts "  • phrases.jsonl             - High-salience phrases with IDs"
puts "  • tagged_corpus.jsonl       - Corpus with phrase annotations"
puts "  • artifacts/                - Matcher files (DAAC, payloads, vocab)"
puts
puts "Next steps:"
puts "  • Export to CoNLL/IOB2 format for NER training (coming soon)"
puts "  • Use tagged corpus with spaCy, Hugging Face, etc."
puts