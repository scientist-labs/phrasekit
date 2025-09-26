# PhraseKit Salience Scoring

## Overview

Salience scoring distinguishes domain-specific terms from generic phrases by comparing their frequency in your domain corpus against a background corpus.

**Goal:** Filter "lysis buffer" (domain term) from "for the" (generic phrase)

## Input Format

### Domain Phrases (from M4 Mining)

```jsonl
{"tokens":["lysis","buffer"],"count":2450}
{"tokens":["for","the"],"count":8500}
{"tokens":["protein","assay"],"count":1200}
```

### Background Phrases

Two options:

**Option 1: Mine from general corpus**
```bash
# Mine Wikipedia/news corpus with same config
phrasekit_mine general_corpus.jsonl mine_config.json background_phrases.jsonl
```

**Option 2: Use provided background frequencies**
```jsonl
{"tokens":["lysis","buffer"],"count":5}
{"tokens":["for","the"],"count":125000}
{"tokens":["protein","assay"],"count":50}
```

## Output Format

High-salience phrases with scores:

```jsonl
{"tokens":["lysis","buffer"],"salience":490.0,"domain_count":2450,"background_count":5,"phrase_id":1000}
{"tokens":["protein","assay"],"salience":24.0,"domain_count":1200,"background_count":50,"phrase_id":1001}
```

**Note:** Generic phrases like "for the" are filtered out due to low salience.

## Configuration

```json
{
  "method": "ratio",
  "min_salience": 2.0,
  "min_domain_count": 10,
  "assign_phrase_ids": true,
  "starting_phrase_id": 1000
}
```

### Fields

- **method**: Scoring algorithm (`"ratio"`, `"pmi"`, or `"tfidf"`)
- **min_salience**: Minimum salience threshold (phrases below this are filtered)
- **min_domain_count**: Minimum count in domain corpus (pre-filter)
- **assign_phrase_ids**: Auto-assign unique IDs to phrases
- **starting_phrase_id**: First phrase ID to assign (default: 1000)

## Scoring Methods

### Ratio (Simplest)

```
salience = domain_count / (background_count + 1)
```

**Intuition:** How many times more frequent in domain vs background?

**Example:**
- "lysis buffer": 2450 / (5 + 1) = 408.3 → HIGH salience
- "for the": 8500 / (125000 + 1) = 0.068 → LOW salience

**When to use:** Simple, interpretable, works well for most cases

### Pointwise Mutual Information (PMI)

```
salience = log2(P(phrase|domain) / P(phrase|background))
```

Where:
- `P(phrase|domain) = domain_count / total_domain_ngrams`
- `P(phrase|background) = background_count / total_background_ngrams`

**Intuition:** Information gain from knowing phrase appears in domain vs background

**When to use:** When you want statistical significance, handles corpus size differences

### TF-IDF Style

```
salience = (domain_count / total_domain_ngrams) * log((total_docs + 1) / (docs_with_phrase + 1))
```

**Intuition:** Balances term frequency with inverse document frequency

**When to use:** When you have document-level information

## Usage

### CLI Tool

```bash
./ext/phrasekit/target/release/phrasekit_score \
  candidate_phrases.jsonl \
  background_phrases.jsonl \
  score_config.json \
  phrases.jsonl
```

**Output:**
```
🎯 PhraseKit Salience Scoring
════════════════════════════════════════
Domain:     candidate_phrases.jsonl
Background: background_phrases.jsonl
Config:     score_config.json
Output:     phrases.jsonl

✓ Loaded config: ratio method, min_salience=2.0

📊 Scoring...
  ✓ Loaded 125,000 domain phrases
  ✓ Loaded 2,500,000 background phrases
  ✓ Computed salience scores

💾 Filtering...
  ✓ 10,243 phrases with salience ≥ 2.0
  ✓ Assigned phrase IDs 1000-11242

✅ Scoring complete!

Top phrases by salience:
  1. lysis buffer → 490.0
  2. western blot → 385.2
  3. pcr master mix → 156.8
```

### Ruby API

```ruby
PhraseKit::Scorer.score(
  domain_path: "candidate_phrases.jsonl",
  background_path: "background_phrases.jsonl",
  output_path: "phrases.jsonl",
  method: :ratio,
  min_salience: 2.0,
  min_domain_count: 10
)
```

## Complete Pipeline

### 1. Mine Domain Corpus

```bash
phrasekit_mine domain_corpus.jsonl mine_config.json candidate_phrases.jsonl
```

### 2. Mine Background Corpus (or use existing)

```bash
# Option A: Mine from general corpus
phrasekit_mine wikipedia.jsonl mine_config.json background_phrases.jsonl

# Option B: Use pre-computed background
# (download from common corpus: Wikipedia, news, etc.)
```

### 3. Score & Filter

```bash
phrasekit_score \
  candidate_phrases.jsonl \
  background_phrases.jsonl \
  score_config.json \
  phrases.jsonl
```

### 4. Build Matching Artifacts (M2)

```bash
phrasekit_build phrases.jsonl build_config.json ./artifacts/
```

Now you have high-value domain phrases ready for corpus tagging!

## Choosing Salience Threshold

### Conservative (High Precision)

```json
{"min_salience": 10.0}
```

- Only extremely domain-specific terms
- Low false positives
- May miss some valid terms

### Balanced (Recommended)

```json
{"min_salience": 2.0}
```

- Good mix of domain terms
- Filters most generic phrases
- Works for most use cases

### Aggressive (High Recall)

```json
{"min_salience": 1.2}
```

- Includes borderline terms
- More false positives
- Better recall for sparse domains

### Adaptive Approach

Start conservative, inspect results, adjust:

```ruby
# Score with multiple thresholds
[1.5, 2.0, 5.0, 10.0].each do |threshold|
  PhraseKit::Scorer.score(
    domain_path: "candidates.jsonl",
    background_path: "background.jsonl",
    output_path: "phrases_#{threshold}.jsonl",
    min_salience: threshold
  )

  count = File.readlines("phrases_#{threshold}.jsonl").size
  puts "Threshold #{threshold}: #{count} phrases"
end

# Inspect results, choose best threshold
```

## Background Corpus Options

### General English

Use large general corpus:
- Wikipedia dump
- Common Crawl
- News articles
- Books corpus (Google Ngrams)

**Best for:** Most domains

### Related Domain

Use corpus from adjacent field:
- Biomedical domain → use PubMed abstracts
- E-commerce → use product catalogs
- Legal → use case law

**Best for:** Highly specialized domains

### Universal Background

Use pre-computed universal n-gram frequencies:
- Google Ngrams (books corpus)
- Web 1T 5-gram corpus

**Best for:** When you don't want to mine background

## Example: Biomedical Products

### Domain Corpus

10M product descriptions from biomedical suppliers

**Top candidates after mining:**
```
lysis buffer → 2,450
for the → 8,500
protein assay kit → 1,200
in a → 12,000
western blot → 1,850
```

### Background Corpus

Wikipedia + PubMed abstracts

**Background frequencies:**
```
lysis buffer → 5
for the → 125,000
protein assay kit → 50
in a → 500,000
western blot → 150
```

### After Scoring (ratio, min_salience=2.0)

```jsonl
{"tokens":["lysis","buffer"],"salience":490.0,"phrase_id":1000}
{"tokens":["protein","assay","kit"],"salience":24.0,"phrase_id":1001}
{"tokens":["western","blot"],"salience":12.3,"phrase_id":1002}
```

**Filtered out:**
- "for the" (salience=0.068)
- "in a" (salience=0.024)

## Performance

- **Scoring speed**: 100K phrases/second
- **Memory**: Scales with background corpus size (~500MB for 1M background phrases)
- **Bottleneck**: Loading background phrases (use binary format for very large backgrounds)

## Best Practices

### Background Corpus Size

- **Minimum**: 10x larger than domain corpus
- **Recommended**: 100x larger
- **Maximum**: Diminishing returns beyond 1000x

### Filtering Strategy

1. **Pre-filter by domain count**: Remove phrases with count < 10
2. **Score against background**
3. **Post-filter by salience**: Keep salience ≥ threshold
4. **Manual review**: Inspect top/bottom phrases, adjust threshold

### Multi-Domain Comparison

For multi-domain corpora, score separately:

```bash
# Domain 1: Biomedical
phrasekit_score bio_candidates.jsonl background.jsonl config.json bio_phrases.jsonl

# Domain 2: Chemistry
phrasekit_score chem_candidates.jsonl background.jsonl config.json chem_phrases.jsonl

# Compare domains
diff <(head -20 bio_phrases.jsonl) <(head -20 chem_phrases.jsonl)
```

## Troubleshooting

### "Too many phrases after filtering"

- Increase `min_salience` threshold
- Increase `min_domain_count` to filter rare phrases
- Check background corpus is representative

### "Too few phrases after filtering"

- Decrease `min_salience` threshold
- Check background corpus isn't domain-specific
- Verify background phrases loaded correctly

### "Generic phrases passing through"

- Background corpus too small or not representative
- Try different scoring method (PMI may work better)
- Increase `min_salience` threshold

## Next: Corpus Tagging

After scoring, you have high-value domain phrases. Next step:

**M6: Corpus Tagging** - Tag original corpus with phrases to generate weak supervision labels

See `docs/TAGGING.md` for details.