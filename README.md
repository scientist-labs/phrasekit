# PhraseKit

Ultra-fast deterministic phrase matching for Ruby using Rust and Aho-Corasick automaton.

PhraseKit provides high-performance phrase recognition over token sequences, designed for search query understanding, NLP pipelines, and information extraction at scale.

## Features

- **Deterministic matching** using Double-Array Aho-Corasick (daachorse)
- **Sub-millisecond performance** for queries with millions of phrases
- **Hot-reloadable** artifacts with zero downtime
- **Thread-safe** operations via Magnus/Rust
- **Multiple matching policies**: leftmost-longest, leftmost-first, salience-max
- **Production-ready** with health checks, stats, and observability

## Installation

Add to your Gemfile:

```ruby
gem 'phrasekit'
```

Or install directly:

```bash
gem install phrasekit
```

## Usage

### Basic Setup

```ruby
require 'phrasekit'

# Load phrase artifacts
PhraseKit.load!(
  automaton_path: "/path/to/phrases.daac",
  payloads_path: "/path/to/payloads.bin",
  manifest_path: "/path/to/phrases.json"
)

# Match tokens
token_ids = [1012, 441, 7788, 902, 1455]  # Your tokenized input
matches = PhraseKit.match_tokens(
  token_ids: token_ids,
  policy: :leftmost_longest,  # or :leftmost_first, :salience_max
  max: 32                      # Maximum matches to return
)

# Returns array of matches:
# [
#   {start: 1, end: 3, phrase_id: 12345, salience: 2.13, count: 314, n: 2},
#   {start: 3, end: 5, phrase_id: 67890, salience: 1.82, count: 271, n: 2}
# ]
```

### Integration with SpellKit

PhraseKit is designed to work with SpellKit for typo correction:

```ruby
class SearchTermExtractor
  def call(text)
    # 1. Tokenize
    tokens = MyTokenizer.tokenize(text)

    # 2. Spell correction (via SpellKit gem)
    corrected = SpellKit.correct_tokens(tokens, guard: :domain)

    # 3. Convert to token IDs
    token_ids = MyTokenizer.to_ids(corrected)

    # 4. Extract phrases
    PhraseKit.match_tokens(token_ids: token_ids, policy: :leftmost_longest)
  end
end
```

### Monitoring

```ruby
# Check health
PhraseKit.healthcheck  # Raises on issues

# Get statistics
PhraseKit.stats
# => {
#   version: "pk-2025-09-25-01",
#   loaded_at: Time,
#   num_patterns: 1_287_345,
#   heap_mb: 142.3,
#   hits_total: 892341,
#   p50_us: 47,
#   p95_us: 189
# }
```

## Architecture

PhraseKit uses:
- **Rust** for core matching logic
- **Magnus** for Ruby-Rust bindings
- **Daachorse** for the Aho-Corasick automaton
- **Static linking** for reliability

## Performance

Target performance with 1-3M phrases:
- p50 < 100µs
- p95 < 500µs
- Memory < 300MB

## Development

```bash
# Setup
bundle install
bundle exec rake compile

# Run tests
bundle exec rspec

# Build gem
gem build phrasekit.gemspec
```

## License

MIT License. See LICENSE.txt for details.