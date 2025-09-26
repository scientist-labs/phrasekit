# PhraseKit Artifact Builder - Input Format

## Overview

The PhraseKit builder compiles phrases into optimized matching artifacts. Input is provided as JSONL (JSON Lines) for efficient streaming of large phrase sets.

## Input Format: phrases.jsonl

Each line is a JSON object representing one phrase:

```jsonl
{"tokens":[100,101],"phrase_id":1000,"salience":2.5,"count":150}
{"tokens":[200,101],"phrase_id":1001,"salience":2.0,"count":100}
{"tokens":[100,101,102],"phrase_id":1002,"salience":3.0,"count":200}
```

### Fields

- **tokens** (required): Array of u32 token IDs representing the phrase
- **phrase_id** (required): Unique u32 identifier for this phrase
- **salience** (required): f32 salience score (typically 0.0-10.0)
- **count** (required): u32 occurrence count in corpus

### Config Format: config.json

Metadata about the build:

```json
{
  "version": "pk-2025-09-26-01",
  "tokenizer": "scientist-v1",
  "separator_id": 4294967294,
  "min_count": 10,
  "salience_threshold": 1.0
}
```

### Fields

- **version** (required): String identifier for this artifact version
- **tokenizer** (required): String identifier for tokenizer used
- **separator_id** (required): u32 separator token ID (must not appear in vocab)
- **min_count** (optional): Minimum count threshold for inclusion
- **salience_threshold** (optional): Minimum salience threshold

## Output Artifacts

Builder generates three files:

1. **phrases.daac**: Binary automaton (daachorse format)
2. **payloads.bin**: Binary payload table (17 bytes per phrase)
3. **manifest.json**: Metadata with checksums and stats

## Usage

```bash
phrasekit build \
  --input phrases.jsonl \
  --config config.json \
  --output ./artifacts/

# Outputs:
#   ./artifacts/phrases.daac
#   ./artifacts/payloads.bin
#   ./artifacts/manifest.json
```

## Validation

Builder performs these validations:

- Token IDs do not contain separator_id
- phrase_id values are unique
- All required fields present
- salience and count are positive
- Automaton build succeeds (no duplicate patterns)

## Example: Minimal Dataset

```jsonl
{"tokens":[1,2],"phrase_id":100,"salience":1.5,"count":50}
{"tokens":[2,3],"phrase_id":101,"salience":2.0,"count":100}
```

```json
{
  "version": "dev-v1",
  "tokenizer": "test",
  "separator_id": 4294967294
}
```