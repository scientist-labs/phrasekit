# Running PhraseKit on Real Data

Guide for processing 10-20M product entries through the full weak supervision pipeline.

## Step 1: Prepare Your Corpus

### Format: JSONL (JSON Lines)

One product per line, newlines in text replaced with spaces:

```jsonl
{"doc_id":"prod_1","tokens":["rat","anti","cdk10","monoclonal","antibody","100ug"]}
{"doc_id":"prod_2","tokens":["western","blot","transfer","buffer","10x","concentrate"]}
{"doc_id":"prod_3","tokens":["protein","assay","kit","bradford","reagent"]}
```

**Required fields:**
- `doc_id` (string): Unique product ID
- `tokens` (array): Pre-tokenized text (lowercase recommended)

### Tokenization Strategy

You need to tokenize your product descriptions before feeding to PhraseKit. Options:

**Simple (fast):**
```ruby
# Lowercase, split on whitespace, remove special chars
text.downcase.split(/\s+/).map { |t| t.gsub(/[^\w-]/, '') }.reject(&:empty?)
```

**Better (with SpellKit):**
```ruby
tokens = text.downcase.split(/\s+/).map { |t| t.gsub(/[^\w-]/, '') }.reject(&:empty?)
SpellKit.correct_tokens(tokens)  # Fix typos before mining
```

**Advanced (domain-aware):**
```ruby
# Preserve technical terms, measurements, catalog numbers
# Split on whitespace but keep:
# - Hyphenated terms: "anti-CD3"
# - Measurements: "100ug", "10x"
# - Catalog numbers: "AB-12345"
```

### Handling Multi-line Text

**Replace newlines with spaces:**
```ruby
text.gsub(/\n+/, ' ').strip
```

**Or preserve paragraph structure:**
```ruby
# If you have multiple fields (title, description, specs)
{
  "doc_id": "prod_1",
  "tokens": tokenize("#{title} #{description} #{specifications}".gsub(/\n+/, ' '))
}
```

## Step 2: Create Corpus Files

### Option A: Single Large File (Recommended)

```ruby
#!/usr/bin/env ruby
require 'json'

File.open("corpus.jsonl", "w") do |f|
  Product.find_each(batch_size: 1000) do |product|
    text = [product.title, product.description, product.specifications]
      .compact
      .join(' ')
      .gsub(/\n+/, ' ')
      .strip

    tokens = text.downcase
      .split(/\s+/)
      .map { |t| t.gsub(/[^\w-]/, '') }
      .reject(&:empty?)

    next if tokens.empty?

    f.puts JSON.generate({
      doc_id: product.id.to_s,
      tokens: tokens
    })
  end
end
```

**For 20M products:**
- File size: ~5-20GB (depending on token count)
- Generation time: 1-2 hours
- PhraseKit handles streaming, so file size is fine

### Option B: Split Into Chunks

If you prefer smaller files for incremental processing:

```ruby
chunk_size = 1_000_000
chunk_num = 0

File.open("corpus_#{chunk_num}.jsonl", "w") do |f|
  Product.find_each(batch_size: 1000).with_index do |product, i|
    if i > 0 && i % chunk_size == 0
      f.close
      chunk_num += 1
      f = File.open("corpus_#{chunk_num}.jsonl", "w")
    end

    # ... same tokenization as above ...
  end
end
```

Generates: `corpus_0.jsonl`, `corpus_1.jsonl`, etc. (1M products each)

## Step 3: Get Background Corpus

You need a general-purpose corpus to distinguish domain-specific terms from common words.

### Option A: Wikipedia N-grams (Recommended)

**Download pre-computed n-grams:**
```bash
# English Wikipedia 2-5 grams (processed)
wget https://example.com/wikipedia-ngrams.jsonl.gz
gunzip wikipedia-ngrams.jsonl.gz
```

Or build yourself:
```ruby
# Extract from Wikipedia dump
# Output: background_phrases.jsonl
# Format: {"tokens":["for","the"],"count":50000}
```

### Option B: Common Crawl

If you have access:
```bash
# Sample from Common Crawl
# Filter to English, extract n-grams
# Much larger but higher quality
```

### Option C: News Corpus

```ruby
# Use news articles corpus
# Good for scientific/technical domains
# Can use PubMed abstracts for biotech
```

### Option D: Quick Start (Small Sample)

For testing, create a minimal background corpus:

```ruby
#!/usr/bin/env ruby
require 'json'

# Common English 2-5 grams with rough frequencies
common_ngrams = {
  ["for", "the"] => 50000,
  ["in", "the"] => 45000,
  ["to", "the"] => 30000,
  ["of", "the"] => 60000,
  ["and", "the"] => 25000,
  ["with", "a"] => 20000,
  ["from", "the"] => 18000,
  ["at", "the"] => 15000,
  # Add more common phrases
}

File.open("background_phrases.jsonl", "w") do |f|
  common_ngrams.each do |tokens, count|
    f.puts JSON.generate({tokens: tokens, count: count})
  end
end
```

**NOTE:** Scoring quality improves with better background corpus. Start simple, refine later.

## Step 4: Test on Sample Data First

**DON'T start with 20M documents!** Test incrementally:

### 4.1 Small Test (1K documents)

```bash
# Extract first 1000 lines
head -n 1000 corpus.jsonl > corpus_1k.jsonl

# Run full pipeline
bundle exec ruby test_pipeline.rb corpus_1k.jsonl
```

**Expected time:** ~5 seconds

### 4.2 Medium Test (100K documents)

```bash
head -n 100000 corpus.jsonl > corpus_100k.jsonl
bundle exec ruby test_pipeline.rb corpus_100k.jsonl
```

**Expected time:** ~1-2 minutes

### 4.3 Large Test (1M documents)

```bash
head -n 1000000 corpus.jsonl > corpus_1m.jsonl
bundle exec ruby test_pipeline.rb corpus_1m.jsonl
```

**Expected time:** ~10-20 minutes

### 4.4 Full Run (20M documents)

Only after validating results on samples!

```bash
bundle exec ruby test_pipeline.rb corpus.jsonl
```

**Expected time:** ~4-8 hours (depending on hardware)

## Step 5: Full Pipeline Script

```ruby
#!/usr/bin/env ruby
require "bundler/setup"
require "phrasekit"
require "json"

corpus_path = ARGV[0] || "corpus.jsonl"
output_dir = ARGV[1] || "phrasekit_output"

FileUtils.mkdir_p(output_dir)

puts "=" * 70
puts "PhraseKit Real Data Pipeline"
puts "=" * 70
puts "Corpus: #{corpus_path}"
puts "Output: #{output_dir}"
puts

# Validate corpus
puts "Validating corpus..."
line_count = `wc -l < #{corpus_path}`.to_i
file_size_mb = File.size(corpus_path) / 1_048_576.0
puts "  Documents: #{line_count}"
puts "  File size: #{file_size_mb.round(2)} MB"
puts

# Step 1: Mine n-grams (10-50K docs/sec)
puts "STEP 1: Mining n-grams..."
start_time = Time.now
candidate_phrases_path = File.join(output_dir, "candidate_phrases.jsonl")

stats = PhraseKit::Miner.mine(
  input_path: corpus_path,
  output_path: candidate_phrases_path,
  min_n: 2,
  max_n: 5,
  min_count: 10  # Adjust based on corpus size
)

mining_time = Time.now - start_time
puts "  ✓ Completed in #{mining_time.round(2)}s"
puts "  ✓ Unique n-grams: #{stats[:unique_ngrams]}"
puts "  ✓ After filtering: #{stats[:ngrams_after_filter]}"
puts "  ✓ Throughput: #{(line_count / mining_time).round(0)} docs/sec"
puts

# Step 2: Score phrases
puts "STEP 2: Scoring by salience..."
start_time = Time.now
phrases_path = File.join(output_dir, "phrases.jsonl")

# Use your background corpus here
background_path = "background_phrases.jsonl"

score_stats = PhraseKit::Scorer.score(
  domain_path: candidate_phrases_path,
  background_path: background_path,
  output_path: phrases_path,
  method: :ratio,
  min_salience: 2.0,
  min_domain_count: 10  # Adjust based on corpus size
)

scoring_time = Time.now - start_time
puts "  ✓ Completed in #{scoring_time.round(2)}s"
puts "  ✓ High-salience phrases: #{score_stats[:after_salience_filter]}"
puts

# Step 3: Build matcher
puts "STEP 3: Building matcher artifacts..."
start_time = Time.now
artifacts_dir = File.join(output_dir, "artifacts")
FileUtils.mkdir_p(artifacts_dir)

build_config = {
  version: "production-v1",
  tokenizer: "whitespace",
  separator_id: 4294967294
}
config_path = File.join(output_dir, "build_config.json")
File.write(config_path, JSON.generate(build_config))

build_cmd = [
  File.expand_path("../ext/phrasekit/target/release/phrasekit_build", __dir__),
  phrases_path,
  config_path,
  artifacts_dir
]

system(build_cmd.shelljoin)
building_time = Time.now - start_time
puts "  ✓ Completed in #{building_time.round(2)}s"
puts

# Step 4: Tag corpus
puts "STEP 4: Tagging corpus with phrases..."
start_time = Time.now
tagged_corpus_path = File.join(output_dir, "tagged_corpus.jsonl")

tag_stats = PhraseKit::Tagger.tag(
  input_path: corpus_path,
  output_path: tagged_corpus_path,
  artifacts_dir: artifacts_dir,
  policy: :leftmost_longest,
  max_spans: 100
)

tagging_time = Time.now - start_time
puts "  ✓ Completed in #{tagging_time.round(2)}s"
puts "  ✓ Documents tagged: #{tag_stats[:documents]}"
puts "  ✓ Total spans: #{tag_stats[:total_spans]}"
puts "  ✓ Coverage: #{((tag_stats[:docs_with_spans].to_f / tag_stats[:documents]) * 100).round(2)}%"
puts "  ✓ Throughput: #{(line_count / tagging_time).round(0)} docs/sec"
puts

# Summary
total_time = mining_time + scoring_time + building_time + tagging_time
puts "=" * 70
puts "Pipeline complete!"
puts "=" * 70
puts "Total time: #{total_time.round(2)}s (#{(total_time / 60).round(2)} minutes)"
puts
puts "Outputs:"
puts "  • #{candidate_phrases_path}"
puts "  • #{phrases_path}"
puts "  • #{tagged_corpus_path}"
puts "  • #{artifacts_dir}/"
puts

# Quick stats
puts "Quick stats:"
puts "  • Phrase candidates: #{stats[:ngrams_after_filter]}"
puts "  • High-value phrases: #{score_stats[:after_salience_filter]}"
puts "  • Span coverage: #{((tag_stats[:docs_with_spans].to_f / tag_stats[:documents]) * 100).round(2)}%"
puts "  • Avg spans/doc: #{tag_stats[:avg_spans_per_doc].round(2)}"
puts

# Top phrases
puts "Top phrases by salience:"
top_phrases = File.readlines(phrases_path)
  .map { |line| JSON.parse(line) }
  .sort_by { |p| -p["salience"] }
  .take(20)

top_phrases.each_with_index do |phrase, i|
  puts "  #{i + 1}. #{phrase["tokens"].join(" ")} (salience=#{phrase["salience"].round(2)}, count=#{phrase["domain_count"]})"
end
```

Save as `scripts/run_pipeline.rb` and run:

```bash
bundle exec ruby scripts/run_pipeline.rb corpus.jsonl output/
```

## Performance Expectations

### For 20M Products

**Assuming:**
- Average 20 tokens per product
- Modern hardware (M1/M2 Mac or similar)
- SSD storage

**Pipeline times:**

1. **Mining (Step 1):** 1-2 hours
   - Throughput: 10K-50K docs/sec
   - Bottleneck: Disk I/O
   - Output: ~500K-2M candidate phrases

2. **Scoring (Step 2):** 5-30 minutes
   - Throughput: 100K phrases/sec
   - Depends on candidate phrase count
   - Output: ~10K-100K high-salience phrases

3. **Building (Step 3):** 1-5 minutes
   - One-time artifact compilation
   - Memory: ~500MB for 50K phrases

4. **Tagging (Step 4):** 1-2 hours
   - Throughput: 50K-100K docs/sec
   - Bottleneck: Disk I/O
   - Output: Tagged corpus with spans

**Total: ~3-5 hours for full pipeline**

### Optimizations

**Parallel Processing:**
```bash
# Split corpus into chunks, process in parallel
split -l 1000000 corpus.jsonl chunk_
parallel bundle exec ruby scripts/run_pipeline.rb ::: chunk_*
# Merge results
```

**Incremental Updates:**
```ruby
# For new products, only mine/tag new data
# Merge with existing phrases
```

## Tuning Parameters

### min_count (Mining)

Adjust based on corpus size:
- **1K docs:** `min_count: 2`
- **100K docs:** `min_count: 10`
- **1M docs:** `min_count: 20`
- **20M docs:** `min_count: 50-100`

**Rule of thumb:** Aim for 50K-500K candidate phrases

### min_salience (Scoring)

Higher = more selective:
- **2.0:** Balanced (recommended starting point)
- **5.0:** Very selective (only highly domain-specific)
- **1.0:** Permissive (may include generic phrases)

**Rule of thumb:** Aim for 10K-50K final phrases

### min_domain_count (Scoring)

Filter rare phrases:
- **10:** Minimum for reliability
- **50:** Good for large corpus
- **100:** Very conservative

## Next Steps

1. ✅ Prepare corpus JSONL
2. ✅ Create/download background corpus
3. ✅ Test on 1K sample
4. ✅ Scale to 100K
5. ✅ Run full pipeline
6. ✅ Review top phrases
7. ✅ Adjust parameters if needed
8. ✅ Export to NER format (coming soon!)

## Troubleshooting

**Out of memory:**
- PhraseKit uses streaming, should handle any corpus size
- If mining fails, reduce `max_n` from 5 to 4

**Too many candidate phrases:**
- Increase `min_count` in mining step
- Will reduce processing time

**Too few final phrases:**
- Decrease `min_salience` in scoring step
- Check your background corpus quality

**Low span coverage:**
- Your phrases may be too specific
- Try lower `min_count` and `min_salience`
- Check tokenization consistency

## Questions?

Open an issue or see:
- `docs/MINING.md`
- `docs/SALIENCE.md`
- `docs/TAGGING.md`