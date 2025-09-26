# PhraseKit N-gram Mining

## Overview

The n-gram miner extracts candidate phrases from a corpus by counting all n-grams (2-5 token sequences) that appear across your documents.

## Input Format: corpus.jsonl

Each line contains a pre-tokenized document:

```jsonl
{"tokens":["rat","cdk10","oligo","design","kit","for","molecular","biology"]}
{"tokens":["mouse","cdk10","protein","assay","buffer","solution"]}
{"tokens":["lysis","buffer","for","cell","culture","applications"]}
```

### Fields

- **tokens** (required): Array of string tokens (lowercase recommended)
- **doc_id** (optional): Document identifier for debugging

### Tokenization

The miner expects **pre-tokenized** input. You must tokenize your corpus before mining:

```ruby
# Example: Tokenize corpus
File.open("corpus.jsonl", "w") do |out|
  raw_documents.each do |doc|
    tokens = your_tokenizer.tokenize(doc.text)
    out.puts({tokens: tokens, doc_id: doc.id}.to_json)
  end
end
```

**Why pre-tokenized?**
- Tokenization is domain-specific (biomedical vs e-commerce vs legal)
- Allows custom tokenizers (Elasticsearch analyzers, sentencepiece, etc.)
- Separates concerns: tokenization → mining → scoring

## Output Format: candidate_phrases.jsonl

Each line contains an n-gram and its frequency:

```jsonl
{"tokens":["rat","cdk10"],"count":150}
{"tokens":["cdk10","oligo"],"count":125}
{"tokens":["lysis","buffer"],"count":80}
{"tokens":["rat","cdk10","oligo"],"count":95}
```

### Fields

- **tokens**: Array of string tokens forming the n-gram
- **count**: Number of times this n-gram appears in the corpus

## Configuration: mine_config.json

```json
{
  "min_n": 2,
  "max_n": 5,
  "min_count": 10
}
```

### Fields

- **min_n** (default: 2): Minimum n-gram length
- **max_n** (default: 5): Maximum n-gram length
- **min_count** (default: 10): Only output n-grams appearing at least this many times

## Usage

### CLI Tool

```bash
./ext/phrasekit/target/release/phrasekit_mine \
  corpus.jsonl \
  mine_config.json \
  candidate_phrases.jsonl

# Output:
# Processing 1,000,000 documents...
# Extracted 2,450,000 n-grams
# After min_count filter: 125,000 n-grams
# Wrote candidate_phrases.jsonl
```

### Ruby API

```ruby
PhraseKit::Miner.mine(
  input_path: "corpus.jsonl",
  output_path: "candidate_phrases.jsonl",
  min_n: 2,
  max_n: 5,
  min_count: 10
)
```

## Performance

The miner is optimized for large corpora:

- **Streaming**: Processes documents one at a time (constant memory)
- **Fast counting**: Uses HashMap with efficient string hashing
- **Typical throughput**: 10K-50K documents/second (depending on document size)

### Memory Usage

Memory scales with **unique n-grams**, not corpus size:
- 100K unique n-grams: ~50MB
- 1M unique n-grams: ~500MB
- 10M unique n-grams: ~5GB

For very large vocabularies, consider:
- Increasing `min_count` to filter rare n-grams early
- Mining in batches and merging counts

## Example: End-to-End Mining

### 1. Prepare Corpus

```ruby
require "json"

# Tokenize raw documents
File.open("corpus.jsonl", "w") do |out|
  Product.find_each do |product|
    tokens = SearchTokenizer.tokenize(product.description)
    out.puts({tokens: tokens, doc_id: product.id}.to_json)
  end
end
```

### 2. Mine N-grams

```bash
./ext/phrasekit/target/release/phrasekit_mine \
  corpus.jsonl \
  mine_config.json \
  candidate_phrases.jsonl
```

### 3. Inspect Results

```ruby
# Top n-grams by frequency
require "json"

ngrams = File.readlines("candidate_phrases.jsonl")
  .map { |line| JSON.parse(line) }
  .sort_by { |ng| -ng["count"] }
  .take(20)

ngrams.each do |ng|
  puts "#{ng["tokens"].join(" ")} → #{ng["count"]} occurrences"
end

# Output:
# lysis buffer → 2,450 occurrences
# rat cdk10 → 1,850 occurrences
# protein assay kit → 1,200 occurrences
```

### 4. Next Steps

After mining, proceed to **Phase 2: Salience Scoring** to identify domain-specific phrases:

```bash
./ext/phrasekit/target/release/phrasekit_score \
  candidate_phrases.jsonl \
  background_phrases.jsonl \
  config.json \
  phrases.jsonl
```

## Algorithm Details

### N-gram Extraction

For each document:
1. Extract all n-grams of length `min_n` to `max_n`
2. Normalize tokens to lowercase
3. Increment count for each n-gram in global HashMap

Example: `["rat", "cdk10", "oligo"]` with `min_n=2, max_n=3`:
- 2-grams: `["rat","cdk10"]`, `["cdk10","oligo"]`
- 3-grams: `["rat","cdk10","oligo"]`

### Frequency Counting

Uses `HashMap<Vec<String>, u32>` for efficient counting:
- Key: n-gram as token vector
- Value: occurrence count
- Time complexity: O(1) average for insert/lookup

### Filtering

After processing all documents:
1. Filter n-grams with `count < min_count`
2. Sort by count (descending) or alphabetically
3. Write to output JSONL

## Best Practices

### Tokenization

1. **Consistent tokenization**: Use the same tokenizer for mining and runtime matching
2. **Case normalization**: Lowercase tokens during tokenization
3. **Stop word handling**: Consider removing common stop words (optional)
4. **Domain-specific rules**: Handle special tokens (CAS numbers, gene symbols, etc.)

### N-gram Length

- **n=2**: Captures basic phrases ("lysis buffer", "protein assay")
- **n=3-4**: Captures compound terms ("pcr master mix", "western blot protocol")
- **n=5+**: Captures longer phrases but more sparse

Typical configuration: `min_n=2, max_n=5`

### Minimum Count

- **Too low**: Includes many noisy/rare phrases
- **Too high**: Misses valid domain terms
- **Recommended**: Start with `min_count=10`, adjust based on corpus size

### Corpus Size

- **Small (1K-10K docs)**: Set `min_count=5`
- **Medium (10K-100K docs)**: Set `min_count=10`
- **Large (100K-1M docs)**: Set `min_count=50`
- **Very large (1M+ docs)**: Set `min_count=100`

## Troubleshooting

### "Out of memory"

- Increase `min_count` to reduce unique n-grams
- Process corpus in batches and merge counts
- Filter stop words during tokenization

### "Too many n-grams"

- Increase `min_count` threshold
- Reduce `max_n` (e.g., only mine 2-3 grams)
- Review tokenization (splitting too aggressively?)

### "Missing expected phrases"

- Lower `min_count` threshold
- Check tokenization (case normalization, splitting)
- Verify phrases actually appear in corpus

## Next: Salience Scoring

After mining, you'll have many candidate phrases including both domain-specific terms ("lysis buffer") and generic phrases ("for the").

Phase 2 (Salience Scoring) filters candidates to keep only high-value domain terms by comparing against a background corpus.

See `docs/SALIENCE.md` for details.