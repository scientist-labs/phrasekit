# PhraseKit Vocabulary Management

## Overview

PhraseKit uses a vocabulary mapping to convert string tokens to u32 token IDs for efficient matching. The vocabulary is generated during artifact building and loaded at runtime.

## Vocabulary Format

### vocab.json

```json
{
  "tokens": {
    "rat": 1,
    "cdk10": 2,
    "oligo": 3,
    "design": 4,
    "protein": 5
  },
  "special_tokens": {
    "<UNK>": 0
  },
  "vocab_size": 6,
  "separator_id": 4294967294
}
```

### Special Tokens

- **`<UNK>` (ID: 0)**: Unknown token placeholder for tokens not in vocabulary
- **Separator (ID: 4294967294)**: Internal separator used by the automaton (never appears in user tokens)

### Token Assignment

Tokens are assigned sequential IDs starting from 1:
1. All unique tokens from the phrase corpus are collected
2. Tokens are sorted alphabetically for deterministic ordering
3. Sequential IDs are assigned (1, 2, 3, ...)
4. Special tokens use reserved IDs (0 for `<UNK>`)

## Generation

The builder automatically generates vocab.json:

```bash
./ext/phrasekit/target/release/phrasekit_build \
  phrases.jsonl \
  config.json \
  ./output/

# Generates:
#   output/phrases.daac
#   output/payloads.bin
#   output/manifest.json
#   output/vocab.json  ← NEW
```

The vocabulary includes every unique token that appears in any phrase.

## Runtime Usage

### Loading

```ruby
PhraseKit.load!(
  automaton_path: "phrases.daac",
  payloads_path: "payloads.bin",
  manifest_path: "manifest.json",
  vocab_path: "vocab.json"  # NEW
)
```

### Encoding Tokens

Convert string tokens to token IDs:

```ruby
token_ids = PhraseKit.encode_tokens(["rat", "cdk10", "oligo"])
# => [1, 2, 3]

# Unknown tokens return <UNK> ID (0)
token_ids = PhraseKit.encode_tokens(["rat", "unknown_token"])
# => [1, 0]
```

### Case Handling

Tokens are normalized to lowercase during encoding:

```ruby
PhraseKit.encode_tokens(["RAT", "Rat", "rat"])
# => [1, 1, 1]  # All map to same ID
```

**Note:** The vocabulary stores tokens in their canonical form (typically lowercase). The builder extracts tokens from phrases.jsonl as-is, so ensure consistent casing in your input data.

## Complete Pipeline

### With SpellKit Integration

```ruby
# 1. Tokenize search query (string → tokens)
tokens = search_tokenizer.tokenize("rat CDK10 oligo design")
# => ["rat", "cdk10", "oligo", "design"]

# 2. Optional: Spell correction
if spell_checker
  tokens = spell_checker.correct_tokens(tokens)
end

# 3. Encode to token IDs
token_ids = PhraseKit.encode_tokens(tokens)
# => [1, 2, 3, 4]

# 4. Match phrases
matches = PhraseKit.match_tokens(token_ids: token_ids)
# => [{start: 0, end: 3, phrase_id: 1000, ...}]
```

### Convenience Method

For the common case, use `match_text_tokens`:

```ruby
matches = PhraseKit.match_text_tokens(
  tokens: ["rat", "cdk10", "oligo"],
  spell_checker: spell_checker,  # optional
  policy: :leftmost_longest
)
```

This internally:
1. Applies spell checking (if provided)
2. Encodes tokens to IDs
3. Matches phrases
4. Returns matches

## Best Practices

### Building Vocabulary

1. **Include all domain terms** - Your phrase corpus should cover domain-specific terms (genes, chemicals, species)
2. **Consistent tokenization** - Use the same tokenization rules during mining and at runtime
3. **Case normalization** - Decide on lowercase vs mixed case and apply consistently
4. **Handle unknowns** - Unknown tokens at runtime will map to `<UNK>` (ID: 0) and won't match phrases

### Runtime

1. **Pre-tokenize** - Apply your search tokenizer before calling PhraseKit
2. **Spell check first** - Correct typos before encoding (unknown tokens can't match)
3. **Cache vocabulary** - Load once at boot, reuse across requests
4. **Monitor unknowns** - Track `<UNK>` rates to identify missing vocabulary

## Vocabulary Size

Typical vocabulary sizes:
- **Small domain** (10K phrases): ~5-20K unique tokens
- **Medium domain** (100K phrases): ~50-200K unique tokens
- **Large domain** (1M phrases): ~500K-2M unique tokens

Memory usage: ~40-80 bytes per token (Ruby Hash overhead)

## Example

See `examples/vocab_example/` for a complete working example with vocabulary generation and encoding.