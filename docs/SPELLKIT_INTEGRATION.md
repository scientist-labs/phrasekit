# SpellKit Integration

PhraseKit and [SpellKit](https://github.com/scientist-labs/spellkit) are designed to work together as complementary tools for building NER pipelines and search term extraction.

## Overview

**PhraseKit**: Fast phrase matching for finding domain-specific multi-token terms
**SpellKit**: Typo correction with domain term protection

Together, they provide a complete preprocessing pipeline:
```
Raw text → Tokenize → SpellKit (correct typos) → PhraseKit (match phrases) → Structured output
```

## Installation

SpellKit is **optional** - PhraseKit works independently. However, for development and testing integration patterns, SpellKit is included as a development dependency.

### For PhraseKit Users (without SpellKit)

```ruby
gem "phrasekit"
```

PhraseKit works fine on its own for phrase matching.

### For Development (with SpellKit)

```ruby
# Gemfile
gem "phrasekit"
gem "spellkit", "~> 0.1.1"
```

Or if working on PhraseKit itself, run `bundle install` (SpellKit is already a dev dependency).

## Usage Pattern

### Basic Integration

```ruby
require "phrasekit"
require "spellkit"

# 1. Load SpellKit (0.1.1+ API)
SpellKit.load!(
  dictionary: SpellKit::DEFAULT_DICTIONARY_URL,  # or local file
  edit_distance: 1,
  protected_terms: ["CDK10", "IL6", "BRCA1", "TP53"],
  skip_patterns: {
    skip_urls: true,
    skip_emails: true,
    skip_code_patterns: true
  }
)

# 2. Load PhraseKit
PhraseKit.load!(
  automaton_path: "artifacts/phrases.daac",
  payloads_path: "artifacts/payloads.bin",
  manifest_path: "artifacts/manifest.json",
  vocab_path: "artifacts/vocab.json"
)

# 3. Process text
text = "I need to sequnce the CDK10 gene"
tokens = text.downcase.split  # Use real tokenizer in production

# 4. Correct typos (preserves protected terms)
corrected = SpellKit.correct_tokens(tokens)
# => ["i", "need", "to", "sequence", "the", "cdk10", "gene"]

# 5. Match phrases
token_ids = PhraseKit.encode_tokens(corrected)
matches = PhraseKit.match_tokens(token_ids: token_ids)
```

### Rails Integration

```ruby
# config/initializers/spellkit.rb
SpellKit.load!(
  dictionary: ENV.fetch("SPELLKIT_DICTIONARY_URL"),
  protected_terms: Rails.application.config.protected_terms,
  skip_patterns: {skip_urls: true, skip_code_patterns: true}
)

# config/initializers/phrasekit.rb
PhraseKit.load!(
  automaton_path: Rails.root.join("data/phrases.daac"),
  payloads_path: Rails.root.join("data/payloads.bin"),
  manifest_path: Rails.root.join("data/manifest.json"),
  vocab_path: Rails.root.join("data/vocab.json")
)

# app/services/search_term_extractor.rb
class SearchTermExtractor
  def call(text)
    tokens = tokenize(text)
    corrected = SpellKit.correct_tokens(tokens)
    token_ids = encode(corrected)
    PhraseKit.match_tokens(token_ids: token_ids, policy: :leftmost_longest)
  end

  private

  def tokenize(text)
    # Your tokenization logic
  end

  def encode(tokens)
    PhraseKit.encode_tokens(tokens)
  end
end
```

## SpellKit 0.1.1+ API Changes

If you're upgrading from SpellKit 0.1.0, note these breaking changes:

### Method Renames
```ruby
# Old (0.1.0)
SpellKit.suggest("word", max: 5)
SpellKit.correct_if_unknown("word", guard: :domain)

# New (0.1.1+)
SpellKit.suggestions("word", 5)
SpellKit.correct("word")  # No guard param needed
```

### Protected Terms Configuration
```ruby
# Old (0.1.0) - guard specified per call
SpellKit.load!(unigrams_path: "...", symbols_path: "...")
result = SpellKit.correct_if_unknown("CDK10", guard: :domain)

# New (0.1.1+) - protection configured at load time
SpellKit.load!(
  dictionary: "...",
  protected_terms: ["CDK10", "IL6", ...]
)
result = SpellKit.correct("CDK10")  # Automatically protected
```

### New Features in 0.1.1
- `correct?(word)` - Check if word is in dictionary
- `skip_patterns` - Filter URLs, emails, code patterns automatically
- Single `dictionary:` parameter instead of multiple file paths
- Better Unicode normalization
- Preserves canonical forms (e.g., "NASA" not "nasa")

## Running the Example

```bash
# Uses real SpellKit if installed, falls back to stub otherwise
bundle exec ruby examples/integration.rb
```

The example demonstrates:
- Loading both gems
- Typo correction with protected terms
- The 0.1.1+ API
- Rails integration patterns

## Why Use Them Together?

**SpellKit before PhraseKit:**
- Fixes typos before phrase matching
- Increases phrase match rate
- Protects domain terms from being "corrected"

**Example:**
```ruby
# Without SpellKit
text = "sequnce the cdk10 gene"
tokens = ["sequnce", "the", "cdk10", "gene"]
matches = PhraseKit.match_text_tokens(tokens: tokens)
# => [] (no match because "sequnce" is misspelled)

# With SpellKit
corrected = SpellKit.correct_tokens(tokens)
# => ["sequence", "the", "cdk10", "gene"]  # typo fixed, CDK10 protected
matches = PhraseKit.match_text_tokens(tokens: corrected)
# => [match for "sequence the cdk10 gene"]
```

## Dependency Injection

PhraseKit doesn't require SpellKit as a runtime dependency. Users can:

1. **Use PhraseKit alone** - Just phrase matching
2. **Add SpellKit** - Enhanced with typo correction
3. **Use different spell checker** - Inject any correction tool

The integration is by convention, not coupling.

## Performance

- **SpellKit**: ~16k corrections/sec (p50: 61µs per token)
- **PhraseKit**: Sub-microsecond matching after loading
- **Combined overhead**: Minimal (~60-100µs per token)

For most applications, the improved match accuracy outweighs the small latency increase.

## See Also

- [SpellKit Documentation](https://github.com/scientist-labs/spellkit)
- [SpellKit 0.1.1 Release Notes](https://github.com/scientist-labs/spellkit/blob/main/CHANGELOG.md)
- [PhraseKit README](../README.md)
- [Integration Example](../examples/integration.rb)