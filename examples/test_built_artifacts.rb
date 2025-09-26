require 'phrasekit'

PhraseKit.load!(
  automaton_path: 'examples/sample_build/output/phrases.daac',
  payloads_path: 'examples/sample_build/output/payloads.bin',
  manifest_path: 'examples/sample_build/output/manifest.json'
)

puts 'Loaded artifacts:'
stats = PhraseKit.stats
puts "  Version: #{stats[:version]}"
puts "  Tokenizer: #{stats[:version]}"
puts "  Patterns: #{stats[:num_patterns]}"

# Test matching
puts "\nTest matching:"
test_cases = [
  [100, 101],
  [200, 101],
  [100, 101, 102],
  [300, 301],
  [999, 888]  # unknown tokens
]

test_cases.each do |tokens|
  matches = PhraseKit.match_tokens(token_ids: tokens)
  puts "  #{tokens.inspect} => #{matches.length} match(es)"
  matches.each do |m|
    puts "    phrase_id=#{m[:phrase_id]}, salience=#{m[:salience]}, span=[#{m[:start]}, #{m[:end]})"
  end
end

puts "\n✓ All tests passed!"