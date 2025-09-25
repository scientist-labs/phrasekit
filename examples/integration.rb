#!/usr/bin/env ruby

require_relative '../lib/phrasekit'
require_relative '../lib/spellkit_stub'

# Example integration showing how PhraseKit and SpellKit work together
# In production, these would be separate gems

puts "=== PhraseKit + SpellKit Integration Example ==="
puts

# Load SpellKit
SpellKit.load!(
  unigrams_path: "models/unigrams.tsv",  # These would be real files
  symbols_path: "models/symbols.txt",
  cas_path: "models/cas.txt",
  manifest_path: "models/spellkit.json",
  edit_distance: 1
)

# Load PhraseKit
PhraseKit.load!(
  automaton_path: "models/phrases.daac",
  payloads_path: "models/payloads.bin",
  manifest_path: "models/phrases.json"
)

puts
puts "=== Example Query Processing ==="
query = "I need rat lyssis CDK10 oligos"
puts "Original query: #{query}"

# Step 1: Tokenize (simplified - in production this would use a real tokenizer)
tokens = query.downcase.split
puts "Tokens: #{tokens.inspect}"

# Step 2: Spell correction with domain protection
corrected = SpellKit.correct_tokens(tokens, guard: :domain)
puts "After correction: #{corrected.inspect}"

# Step 3: Convert to token IDs (stub - would use real tokenizer)
token_ids = corrected.map.with_index { |_, i| 1000 + i }
puts "Token IDs: #{token_ids.inspect}"

# Step 4: Phrase matching
matches = PhraseKit.match_tokens(token_ids: token_ids, policy: :leftmost_longest)
puts "Matches: #{matches.inspect} (empty in stub)"

puts
puts "=== Status Check ==="
puts "PhraseKit stats: #{PhraseKit.stats}"
puts "SpellKit stats: #{SpellKit.stats}"
puts "PhraseKit health: #{PhraseKit.healthcheck}"
puts "SpellKit health: #{SpellKit.healthcheck}"

puts
puts "=== Rails Integration Pattern ==="
puts <<~RUBY
  class SearchTermExtractor
    def call(text)
      tokens = MyTokenizer.tokenize(text)
      corrected = SpellKit.correct_tokens(tokens, guard: :domain)
      token_ids = MyTokenizer.to_ids(corrected)
      PhraseKit.match_tokens(token_ids: token_ids, policy: :leftmost_longest, max: 32)
    end
  end
RUBY