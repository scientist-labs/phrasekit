# PhraseKit Artifact Builder

Production-ready CLI tool for compiling phrase datasets into optimized matching artifacts.

## Installation

The builder is included in the phrasekit gem. Build it with:

```bash
cargo build --release --bin phrasekit_build
```

Binary location: `ext/phrasekit/target/release/phrasekit_build`

## Quick Start

```bash
# 1. Prepare your input data
cat > phrases.jsonl <<EOF
{"tokens":[100,101],"phrase_id":1000,"salience":2.5,"count":150}
{"tokens":[200,101],"phrase_id":1001,"salience":2.0,"count":100}
EOF

# 2. Create config
cat > config.json <<EOF
{
  "version": "my-phrases-v1",
  "tokenizer": "my-tokenizer-v1",
  "separator_id": 4294967294
}
EOF

# 3. Build artifacts
./ext/phrasekit/target/release/phrasekit_build \
  phrases.jsonl \
  config.json \
  ./output/

# 4. Use in Ruby
PhraseKit.load!(
  automaton_path: "output/phrases.daac",
  payloads_path: "output/payloads.bin",
  manifest_path: "output/manifest.json"
)
```

## Input Format

### phrases.jsonl (JSONL format)

Each line is a JSON object:

```jsonl
{"tokens":[1,2,3],"phrase_id":100,"salience":2.5,"count":150}
```

**Required fields:**
- `tokens`: Array of u32 token IDs
- `phrase_id`: Unique u32 identifier
- `salience`: f32 salience score (typically 0.0-10.0)
- `count`: u32 corpus occurrence count

### config.json

Build configuration:

```json
{
  "version": "pk-2025-09-26-01",
  "tokenizer": "scientist-v1",
  "separator_id": 4294967294,
  "min_count": 10,
  "salience_threshold": 1.0
}
```

**Required fields:**
- `version`: Artifact version identifier
- `tokenizer`: Tokenizer version identifier
- `separator_id`: Reserved token ID (must not appear in vocab)

**Optional fields:**
- `min_count`: Minimum occurrence threshold (filters low-frequency phrases)
- `salience_threshold`: Minimum salience threshold

## Output Artifacts

The builder generates three files:

### phrases.daac
Binary automaton in daachorse format. Enables sub-millisecond pattern matching.

### payloads.bin
Binary payload table (17 bytes per phrase):
- phrase_id (u32, 4 bytes)
- salience (f32, 4 bytes)
- count (u32, 4 bytes)
- padding (4 bytes)
- n (u8, 1 byte) - phrase length

### manifest.json
Metadata with build information:
```json
{
  "version": "pk-2025-09-26-01",
  "tokenizer": "scientist-v1",
  "num_patterns": 10,
  "min_count": 10,
  "salience_threshold": 1.0,
  "built_at": "2025-09-26T19:18:05Z",
  "separator_id": 4294967294
}
```

## Validation

The builder performs these validations:

✓ Token IDs do not contain separator_id
✓ phrase_id values are unique
✓ All required fields present
✓ salience and count are positive
✓ Automaton builds successfully (no duplicate patterns)

Warnings are printed for:
- Phrases filtered by min_count
- Phrases filtered by salience_threshold
- Duplicate phrase_ids (later occurrences skipped)
- Invalid token sequences

## Examples

See `examples/sample_build/` for a complete working example.

## Performance

Typical build performance on Apple M1:
- 10K phrases: ~50ms
- 100K phrases: ~500ms
- 1M phrases: ~5s

Memory usage scales with automaton size (typically ~100-300 bytes per phrase).

## Troubleshooting

### Error: "Tokens contain separator_id"
Ensure your separator_id (default: 4294967294) is reserved and never appears in your vocabulary.

### Error: "Duplicate phrase_id"
Each phrase must have a unique phrase_id. Check your input data for duplicates.

### Error: "No valid phrases to build"
All phrases were filtered out. Check min_count and salience_threshold settings.

## Integration

After building, load artifacts in your Rails initializer:

```ruby
# config/initializers/phrasekit.rb
PhraseKit.load!(
  automaton_path: Rails.root.join("models/phrases.daac"),
  payloads_path: Rails.root.join("models/payloads.bin"),
  manifest_path: Rails.root.join("models/phrases.json")
)
```

For hot-reload support, simply call `load!` again with updated artifacts.