# Corpus Tagging

## Overview

The corpus tagging tool takes a pre-tokenized corpus and uses the PhraseKit matcher to annotate it with phrase spans. This produces a tagged corpus ready for NER model training.

## Pipeline Position

```
Mining          Scoring         Building        Tagging         Export
──────────      ───────────     ────────────    ───────────     ──────────
corpus.jsonl    Filter by       Build matcher   Tag corpus      Export to
10M docs        salience        artifacts       with spans      NER formats
    ↓               ↓               ↓               ↓               ↓
candidate_      phrases.jsonl   Matcher ready   tagged_corpus   CoNLL/IOB2
phrases         10K terms       (DAAC+bins)     with phrase     train/dev/test
150K n-grams                                    annotations
```

## Input Format

### Corpus (JSONL)
```jsonl
{"doc_id": "doc_1", "tokens": ["the", "rat", "cdk10", "oligo", "was", "used"]}
{"doc_id": "doc_2", "tokens": ["protein", "assay", "buffer", "preparation"]}
```

**Required fields:**
- `doc_id` (string): Unique document identifier
- `tokens` (array): Pre-tokenized text

### Matcher Artifacts
- `phrases.daac` - Aho-Corasick automaton
- `payloads.bin` - Phrase payloads
- `manifest.json` - Metadata
- `vocab.json` - Token vocabulary

## Output Format

### Tagged Corpus (JSONL)
```jsonl
{
  "doc_id": "doc_1",
  "tokens": ["the", "rat", "cdk10", "oligo", "was", "used"],
  "spans": [
    {"start": 1, "end": 4, "phrase_id": 1000, "label": "PHRASE"}
  ]
}
```

**Fields:**
- `doc_id` (string): Original document ID
- `tokens` (array): Original tokens
- `spans` (array): Phrase annotations
  - `start` (int): Token index (inclusive)
  - `end` (int): Token index (exclusive)
  - `phrase_id` (int): Phrase identifier
  - `label` (string): Entity type (default: "PHRASE")

**Note:** Spans use Python-style slicing: `tokens[start:end]`

## CLI Usage

```bash
./ext/phrasekit/target/release/phrasekit_tag \
  corpus.jsonl \
  tag_config.json \
  tagged_corpus.jsonl
```

### Configuration (tag_config.json)

```json
{
  "automaton_path": "artifacts/phrases.daac",
  "payloads_path": "artifacts/payloads.bin",
  "manifest_path": "artifacts/manifest.json",
  "vocab_path": "artifacts/vocab.json",
  "policy": "leftmost_longest",
  "max_spans": 100,
  "label": "PHRASE"
}
```

**Parameters:**
- `automaton_path`: Path to DAAC file
- `payloads_path`: Path to payloads binary
- `manifest_path`: Path to manifest JSON
- `vocab_path`: Path to vocabulary JSON
- `policy`: Matching policy (`leftmost_longest`, `leftmost_first`, `all`)
- `max_spans`: Maximum spans per document (default: 100)
- `label`: Entity label for spans (default: "PHRASE")

## Ruby API

```ruby
require "phrasekit"

# Tag corpus
stats = PhraseKit::Tagger.tag(
  input_path: "corpus.jsonl",
  output_path: "tagged_corpus.jsonl",
  artifacts_dir: "./artifacts",
  policy: :leftmost_longest,
  max_spans: 100
)
# => {documents: 1000, total_spans: 5234, avg_spans_per_doc: 5.2}
```

**Parameters:**
- `input_path`: Path to corpus JSONL file
- `output_path`: Path for tagged corpus output
- `artifacts_dir`: Directory containing matcher artifacts
- `policy`: Matching policy (`:leftmost_longest`, `:leftmost_first`, `:all`)
- `max_spans`: Maximum spans per document
- `label`: Entity label (default: "PHRASE")
- `config_path`: Optional path to config JSON (auto-generated if not provided)

## Matching Policies

### leftmost_longest (Recommended)
Prioritizes longer matches when phrases overlap:

```
Tokens: ["lysis", "buffer", "solution"]
Phrases: ["lysis", "buffer"], ["lysis", "buffer", "solution"]
Match: "lysis buffer solution" (start=0, end=3)
```

### leftmost_first
Takes first match encountered, then continues:

```
Tokens: ["lysis", "buffer", "solution"]
Phrases: ["lysis", "buffer"], ["buffer", "solution"]
Matches: "lysis buffer" (start=0, end=2)
```

### all
Returns all overlapping matches:

```
Tokens: ["lysis", "buffer", "solution"]
Phrases: ["lysis", "buffer"], ["buffer", "solution"], ["lysis", "buffer", "solution"]
Matches:
  - "lysis buffer" (start=0, end=2)
  - "buffer solution" (start=1, end=3)
  - "lysis buffer solution" (start=0, end=3)
```

## Example

### Input Corpus (corpus.jsonl)
```jsonl
{"doc_id": "doc_1", "tokens": ["the", "rat", "cdk10", "oligo", "was", "used", "with", "lysis", "buffer"]}
{"doc_id": "doc_2", "tokens": ["protein", "assay", "buffer", "is", "required"]}
```

### Matcher Artifacts
Built from phrases with IDs:
- 1000: "rat cdk10 oligo"
- 1001: "lysis buffer"
- 1002: "protein assay buffer"

### Command
```bash
./ext/phrasekit/target/release/phrasekit_tag \
  corpus.jsonl \
  tag_config.json \
  tagged_corpus.jsonl
```

### Output (tagged_corpus.jsonl)
```jsonl
{"doc_id":"doc_1","tokens":["the","rat","cdk10","oligo","was","used","with","lysis","buffer"],"spans":[{"start":1,"end":4,"phrase_id":1000,"label":"PHRASE"},{"start":7,"end":9,"phrase_id":1001,"label":"PHRASE"}]}
{"doc_id":"doc_2","tokens":["protein","assay","buffer","is","required"],"spans":[{"start":0,"end":3,"phrase_id":1002,"label":"PHRASE"}]}
```

**Pretty-printed:**
```json
{
  "doc_id": "doc_1",
  "tokens": ["the", "rat", "cdk10", "oligo", "was", "used", "with", "lysis", "buffer"],
  "spans": [
    {"start": 1, "end": 4, "phrase_id": 1000, "label": "PHRASE"},
    {"start": 7, "end": 9, "phrase_id": 1001, "label": "PHRASE"}
  ]
}
```

## Performance

- **Tagging speed**: 50K-100K documents/second
- **Memory**: Constant per document + matcher size (~100MB for 10K phrases)
- **Bottleneck**: I/O for reading/writing JSONL

## Best Practices

### 1. Use leftmost_longest for NER training
This policy produces non-overlapping spans, which most NER models expect.

### 2. Set reasonable max_spans
Prevents runaway matching in edge cases. Default of 100 is usually sufficient.

### 3. Validate corpus format
Ensure all documents have `doc_id` and `tokens` fields before tagging.

### 4. Monitor span statistics
Low average spans per document may indicate:
- Phrases don't match corpus domain
- Vocabulary mismatch between training and tagging
- Too-strict salience filtering in M5

### 5. Preserve original corpus
Tag to a new file to keep original corpus intact.

## Troubleshooting

### Problem: No spans found
**Cause**: Vocabulary mismatch or missing artifacts
**Solution**:
- Verify vocab.json tokens match corpus tokens (case-sensitive after normalization)
- Check that artifacts were built from same phrase list
- Ensure tokenization is consistent

### Problem: Too many overlapping spans
**Cause**: Using `all` policy with many phrase variants
**Solution**: Switch to `leftmost_longest` policy

### Problem: Memory usage high
**Cause**: Large matcher or very long documents
**Solution**:
- Process corpus in batches
- Increase max_spans limit if hitting it
- Split very long documents

### Problem: Slow tagging
**Cause**: Large corpus or slow I/O
**Solution**:
- Use SSD for corpus storage
- Process in parallel (multiple processes)
- Consider streaming if memory-constrained

## Integration with NER Export

The tagged corpus output is designed as input to the NER export tool:

```bash
# Tag corpus
./ext/phrasekit/target/release/phrasekit_tag \
  corpus.jsonl tag_config.json tagged_corpus.jsonl

# Export to CoNLL format
./ext/phrasekit/target/release/phrasekit_export \
  tagged_corpus.jsonl export_config.json ./ner_data/
```

Output ready for training with spaCy, Hugging Face Transformers, or other NER frameworks.

## Complete Pipeline Example

```ruby
require "phrasekit"

# Mine n-grams from corpus
PhraseKit::Miner.mine(
  input_path: "corpus.jsonl",
  output_path: "candidate_phrases.jsonl",
  min_count: 10
)

# Score and filter by salience
PhraseKit::Scorer.score(
  domain_path: "candidate_phrases.jsonl",
  background_path: "background_phrases.jsonl",
  output_path: "phrases.jsonl",
  min_salience: 2.0
)

# Build matcher artifacts
system("./ext/phrasekit/target/release/phrasekit_build \
  phrases.jsonl build_config.json ./artifacts/")

# Tag corpus with phrase spans
stats = PhraseKit::Tagger.tag(
  input_path: "corpus.jsonl",
  output_path: "tagged_corpus.jsonl",
  artifacts_dir: "./artifacts"
)

puts "Tagged #{stats[:documents]} documents with #{stats[:total_spans]} spans"
```

## Next Steps

After tagging, use the export tool to generate NER training data in standard formats:
- CoNLL/IOB2 format
- Hugging Face datasets
- Prodigy format
- Train/dev/test splits