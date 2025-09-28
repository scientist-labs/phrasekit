#!/usr/bin/env ruby

require "bundler/setup"
require "phrasekit"

# Try to load the real SpellKit gem, fall back to stub if not available
begin
  require "spellkit"
  puts "Using real SpellKit gem (#{SpellKit::VERSION})"
rescue LoadError
  require_relative '../lib/spellkit_stub'
  puts "Using SpellKit stub (real gem not installed)"
end

# Example integration showing how PhraseKit and SpellKit work together
# In production, these would be separate gems
# This example uses SpellKit 0.1.1+ API
#
# NOTE: This is a demonstration example showing API usage patterns.
# To see a fully working example, run: bundle exec ruby examples/end_to_end_demo.rb

puts "=== PhraseKit + SpellKit Integration Example ==="
puts "NOTE: This demonstrates the API pattern. For a working demo, run: examples/end_to_end_demo.rb"
puts

# Load SpellKit (0.1.1+ API)
# When using the real gem, it can download and cache the default dictionary
# The stub doesn't need a real dictionary file
dictionary_source = defined?(SpellKit::DEFAULT_DICTIONARY_URL) ?
  SpellKit::DEFAULT_DICTIONARY_URL :
  "models/dictionary.tsv"

puts "Loading SpellKit with dictionary: #{dictionary_source}"

SpellKit.load!(
  dictionary: dictionary_source,
  edit_distance: 1,
  frequency_threshold: 0,
  protected_terms: ["CDK10", "IL6", "IL-6", "BRCA1", "BRCA2", "TP53", "EGFR"],
  skip_patterns: {
    skip_urls: true,
    skip_emails: true,
    skip_code_patterns: true
  }
)

puts "SpellKit loaded successfully!"
puts

# Load PhraseKit (skipped - requires real artifacts)
# In production, you would load like this:
# PhraseKit.load!(
#   automaton_path: "models/phrases.daac",
#   payloads_path: "models/payloads.bin",
#   manifest_path: "models/phrases.json",
#   vocab_path: "models/vocab.json"
# )

puts
puts "=== Example Query Processing ==="
query = "I need to sequnce the CDK10 gene with helllo world"
puts "Original query: #{query}"

# Step 1: Tokenize (simplified - in production this would use a real tokenizer)
tokens = query.downcase.split
puts "Tokens: #{tokens.inspect}"

# Step 2: Spell correction (protected terms automatically preserved in 0.1.1+)
corrected = SpellKit.correct_tokens(tokens)
puts "After correction: #{corrected.inspect}"
puts "  (Note: typos corrected, but 'cdk10' protected)"

# Step 3: Convert to token IDs (would use real tokenizer in production)
# token_ids = MyTokenizer.to_ids(corrected)
# puts "Token IDs: #{token_ids.inspect}"

# Step 4: Phrase matching (requires loaded PhraseKit)
# matches = PhraseKit.match_tokens(token_ids: token_ids, policy: :leftmost_longest)
# puts "Matches: #{matches.inspect}"

puts
puts "=== SpellKit 0.1.1+ Features ==="
puts "Check if word is correct:"
puts "  SpellKit.correct?('hello') => #{SpellKit.correct?('hello')}"
puts "  SpellKit.correct?('helllo') => #{SpellKit.correct?('helllo')}"
puts "  SpellKit.correct?('CDK10') => #{SpellKit.correct?('CDK10')} (protected term)"
puts

puts "Get suggestions:"
suggestions = SpellKit.suggestions("sequnce", 3)
puts "  SpellKit.suggestions('sequnce', 3) =>"
suggestions.each do |s|
  puts "    #{s.inspect}"
end
puts

puts "Correct words:"
puts "  SpellKit.correct('helllo') => #{SpellKit.correct('helllo').inspect}"
puts "  SpellKit.correct('sequnce') => #{SpellKit.correct('sequnce').inspect}"
puts "  SpellKit.correct('CDK10') => #{SpellKit.correct('CDK10').inspect} (protected)"

puts
puts "=== Status Check ==="
puts "SpellKit stats: #{SpellKit.stats}"
puts "SpellKit health: #{SpellKit.healthcheck}"
# puts "PhraseKit stats: #{PhraseKit.stats}"  # Requires loaded matcher
# puts "PhraseKit health: #{PhraseKit.healthcheck}"

puts
puts "=== Rails Integration Pattern (0.1.1+ API) ==="
puts <<~RUBY
  class SearchTermExtractor
    def call(text)
      tokens = MyTokenizer.tokenize(text)

      # SpellKit 0.1.1+: No guard parameter needed
      # Protected terms are configured at load! time
      corrected = SpellKit.correct_tokens(tokens)

      token_ids = MyTokenizer.to_ids(corrected)
      PhraseKit.match_tokens(token_ids: token_ids, policy: :leftmost_longest, max: 32)
    end
  end

  # Initialize in Rails initializer:
  # config/initializers/spellkit.rb
  SpellKit.load!(
    dictionary: ENV.fetch("SPELLKIT_DICTIONARY_URL"),
    protected_terms: ["CDK10", "IL6", "BRCA1", ...],
    skip_patterns: {skip_urls: true, skip_emails: true}
  )
RUBY