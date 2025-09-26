use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs::File;
use std::io::{BufRead, BufReader, BufWriter, Write};

#[derive(Debug, Deserialize)]
struct Document {
    tokens: Vec<String>,
    #[serde(default)]
    doc_id: Option<String>,
}

#[derive(Debug, Deserialize)]
struct MineConfig {
    #[serde(default = "default_min_n")]
    min_n: usize,
    #[serde(default = "default_max_n")]
    max_n: usize,
    #[serde(default = "default_min_count")]
    min_count: u32,
}

fn default_min_n() -> usize {
    2
}

fn default_max_n() -> usize {
    5
}

fn default_min_count() -> u32 {
    10
}

#[derive(Debug, Serialize)]
struct Ngram {
    tokens: Vec<String>,
    count: u32,
}

#[derive(Debug)]
struct MiningStats {
    total_docs: usize,
    total_tokens: usize,
    total_ngrams_extracted: usize,
    unique_ngrams: usize,
    ngrams_after_filter: usize,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().collect();

    if args.len() < 4 {
        eprintln!("Usage: phrasekit_mine <corpus.jsonl> <config.json> <output.jsonl>");
        eprintln!("\nExample:");
        eprintln!("  phrasekit_mine corpus.jsonl mine_config.json candidate_phrases.jsonl");
        std::process::exit(1);
    }

    let corpus_path = &args[1];
    let config_path = &args[2];
    let output_path = &args[3];

    println!("🔍 PhraseKit N-gram Miner");
    println!("════════════════════════════════════════");
    println!("Corpus:  {}", corpus_path);
    println!("Config:  {}", config_path);
    println!("Output:  {}", output_path);
    println!();

    // Load config
    let config = load_config(config_path)?;
    println!("✓ Loaded config:");
    println!("  min_n: {}", config.min_n);
    println!("  max_n: {}", config.max_n);
    println!("  min_count: {}", config.min_count);

    if config.min_n < 1 || config.max_n > 10 || config.min_n > config.max_n {
        return Err("Invalid config: min_n must be >= 1, max_n must be <= 10, and min_n <= max_n".into());
    }

    // Mine n-grams
    println!("\n📊 Mining n-grams...");
    let (ngram_counts, mut stats) = mine_ngrams(corpus_path, &config)?;

    // Write results
    println!("\n💾 Writing results...");
    stats.ngrams_after_filter = write_ngrams(output_path, ngram_counts, config.min_count)?;

    // Summary
    println!("\n✅ Mining complete!");
    println!("\n📈 Statistics:");
    println!("  Total documents:     {}", stats.total_docs);
    println!("  Total tokens:        {}", stats.total_tokens);
    println!("  N-grams extracted:   {}", stats.total_ngrams_extracted);
    println!("  Unique n-grams:      {}", stats.unique_ngrams);
    println!("  After min_count={}:  {}", config.min_count, stats.ngrams_after_filter);
    println!("\n💡 Next step: Run salience scoring on {}", output_path);

    Ok(())
}

fn load_config(path: &str) -> Result<MineConfig, Box<dyn std::error::Error>> {
    let file = File::open(path)?;
    let config: MineConfig = serde_json::from_reader(file)?;
    Ok(config)
}

fn mine_ngrams(
    corpus_path: &str,
    config: &MineConfig,
) -> Result<(HashMap<Vec<String>, u32>, MiningStats), Box<dyn std::error::Error>> {
    let file = File::open(corpus_path)?;
    let reader = BufReader::new(file);

    let mut ngram_counts: HashMap<Vec<String>, u32> = HashMap::new();
    let mut stats = MiningStats {
        total_docs: 0,
        total_tokens: 0,
        total_ngrams_extracted: 0,
        unique_ngrams: 0,
        ngrams_after_filter: 0,
    };

    for (line_num, line) in reader.lines().enumerate() {
        let line = line?;

        if line.trim().is_empty() {
            continue;
        }

        let doc: Document = match serde_json::from_str(&line) {
            Ok(d) => d,
            Err(e) => {
                eprintln!("⚠️  Line {}: Failed to parse: {}", line_num + 1, e);
                continue;
            }
        };

        stats.total_docs += 1;
        stats.total_tokens += doc.tokens.len();

        // Extract n-grams from document
        for n in config.min_n..=config.max_n {
            if doc.tokens.len() < n {
                continue;
            }

            for i in 0..=(doc.tokens.len() - n) {
                let ngram: Vec<String> = doc.tokens[i..i + n]
                    .iter()
                    .map(|t| t.to_lowercase())
                    .collect();

                *ngram_counts.entry(ngram).or_insert(0) += 1;
                stats.total_ngrams_extracted += 1;
            }
        }

        if stats.total_docs % 10000 == 0 {
            println!("  Processed {} documents...", stats.total_docs);
        }
    }

    stats.unique_ngrams = ngram_counts.len();
    println!("  ✓ Processed {} documents", stats.total_docs);
    println!("  ✓ Extracted {} unique n-grams", stats.unique_ngrams);

    Ok((ngram_counts, stats))
}

fn write_ngrams(
    output_path: &str,
    ngram_counts: HashMap<Vec<String>, u32>,
    min_count: u32,
) -> Result<usize, Box<dyn std::error::Error>> {
    let file = File::create(output_path)?;
    let mut writer = BufWriter::new(file);

    // Sort by count (descending) for better readability
    let mut ngrams: Vec<(Vec<String>, u32)> = ngram_counts
        .into_iter()
        .filter(|(_, count)| *count >= min_count)
        .collect();

    ngrams.sort_by(|a, b| b.1.cmp(&a.1));

    let count = ngrams.len();
    for (tokens, count) in ngrams {
        let ngram = Ngram { tokens, count };
        let json = serde_json::to_string(&ngram)?;
        writeln!(writer, "{}", json)?;
    }

    writer.flush()?;
    println!("  ✓ Wrote {} n-grams to {}", count, output_path);

    Ok(count)
}