use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs::File;
use std::io::{BufRead, BufReader, BufWriter, Write};

#[derive(Debug, Deserialize)]
struct InputNgram {
    tokens: Vec<String>,
    count: u32,
}

#[derive(Debug, Deserialize)]
struct ScoreConfig {
    #[serde(default = "default_method")]
    method: String,
    #[serde(default = "default_min_salience")]
    min_salience: f32,
    #[serde(default = "default_min_domain_count")]
    min_domain_count: u32,
    #[serde(default = "default_assign_phrase_ids")]
    assign_phrase_ids: bool,
    #[serde(default = "default_starting_phrase_id")]
    starting_phrase_id: u32,
}

fn default_method() -> String {
    "ratio".to_string()
}

fn default_min_salience() -> f32 {
    2.0
}

fn default_min_domain_count() -> u32 {
    10
}

fn default_assign_phrase_ids() -> bool {
    true
}

fn default_starting_phrase_id() -> u32 {
    1000
}

#[derive(Debug, Serialize, Deserialize)]
struct OutputPhrase {
    tokens: Vec<String>,
    salience: f32,
    #[serde(skip_serializing_if = "Option::is_none")]
    phrase_id: Option<u32>,
    domain_count: u32,
    background_count: u32,
}

#[derive(Debug)]
struct ScoringStats {
    domain_phrases: usize,
    background_phrases: usize,
    after_domain_filter: usize,
    after_salience_filter: usize,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().collect();

    if args.len() < 5 {
        eprintln!("Usage: phrasekit_score <domain.jsonl> <background.jsonl> <config.json> <output.jsonl>");
        eprintln!("\nExample:");
        eprintln!("  phrasekit_score candidate_phrases.jsonl background_phrases.jsonl score_config.json phrases.jsonl");
        std::process::exit(1);
    }

    let domain_path = &args[1];
    let background_path = &args[2];
    let config_path = &args[3];
    let output_path = &args[4];

    println!("🎯 PhraseKit Salience Scoring");
    println!("════════════════════════════════════════");
    println!("Domain:     {}", domain_path);
    println!("Background: {}", background_path);
    println!("Config:     {}", config_path);
    println!("Output:     {}", output_path);
    println!();

    // Load config
    let config = load_config(config_path)?;
    println!("✓ Loaded config:");
    println!("  method: {}", config.method);
    println!("  min_salience: {}", config.min_salience);
    println!("  min_domain_count: {}", config.min_domain_count);

    // Validate method
    if !["ratio", "pmi", "tfidf"].contains(&config.method.as_str()) {
        return Err(format!("Invalid method: {}. Must be 'ratio', 'pmi', or 'tfidf'", config.method).into());
    }

    // Load phrases
    println!("\n📊 Loading phrases...");
    let domain_phrases = load_phrases(domain_path)?;
    println!("  ✓ Loaded {} domain phrases", domain_phrases.len());

    let background_phrases = load_phrases(background_path)?;
    println!("  ✓ Loaded {} background phrases", background_phrases.len());

    // Score and filter
    println!("\n🎯 Scoring...");
    let (scored_phrases, stats) = score_phrases(domain_phrases, background_phrases, &config)?;

    // Write output
    println!("\n💾 Writing results...");
    write_phrases(output_path, scored_phrases, &config)?;

    // Summary
    println!("\n✅ Scoring complete!");
    println!("\n📈 Statistics:");
    println!("  Domain phrases:           {}", stats.domain_phrases);
    println!("  Background phrases:       {}", stats.background_phrases);
    println!("  After domain filter:      {}", stats.after_domain_filter);
    println!("  After salience filter:    {}", stats.after_salience_filter);

    if config.assign_phrase_ids && stats.after_salience_filter > 0 {
        let end_id = config.starting_phrase_id + stats.after_salience_filter as u32 - 1;
        println!("  Phrase IDs assigned:      {} - {}", config.starting_phrase_id, end_id);
    }

    println!("\n💡 Next step: Build matching artifacts with phrasekit_build");

    Ok(())
}

fn load_config(path: &str) -> Result<ScoreConfig, Box<dyn std::error::Error>> {
    let file = File::open(path)?;
    let config: ScoreConfig = serde_json::from_reader(file)?;
    Ok(config)
}

fn load_phrases(path: &str) -> Result<HashMap<Vec<String>, u32>, Box<dyn std::error::Error>> {
    let file = File::open(path)?;
    let reader = BufReader::new(file);
    let mut phrases = HashMap::new();

    for (line_num, line) in reader.lines().enumerate() {
        let line = line?;
        if line.trim().is_empty() {
            continue;
        }

        let ngram: InputNgram = match serde_json::from_str(&line) {
            Ok(n) => n,
            Err(e) => {
                eprintln!("⚠️  Line {}: Failed to parse: {}", line_num + 1, e);
                continue;
            }
        };

        // Normalize to lowercase
        let tokens: Vec<String> = ngram.tokens.iter().map(|t| t.to_lowercase()).collect();
        phrases.insert(tokens, ngram.count);
    }

    Ok(phrases)
}

fn score_phrases(
    domain_phrases: HashMap<Vec<String>, u32>,
    background_phrases: HashMap<Vec<String>, u32>,
    config: &ScoreConfig,
) -> Result<(Vec<OutputPhrase>, ScoringStats), Box<dyn std::error::Error>> {
    let mut scored = Vec::new();
    let mut stats = ScoringStats {
        domain_phrases: domain_phrases.len(),
        background_phrases: background_phrases.len(),
        after_domain_filter: 0,
        after_salience_filter: 0,
    };

    // Compute total counts for PMI
    let total_domain: u64 = domain_phrases.values().map(|&c| c as u64).sum();
    let total_background: u64 = background_phrases.values().map(|&c| c as u64).sum();

    for (tokens, domain_count) in domain_phrases {
        // Filter by minimum domain count
        if domain_count < config.min_domain_count {
            continue;
        }
        stats.after_domain_filter += 1;

        // Get background count (default to 0 if not found)
        let background_count = background_phrases.get(&tokens).copied().unwrap_or(0);

        // Compute salience based on method
        let salience = match config.method.as_str() {
            "ratio" => compute_ratio_salience(domain_count, background_count),
            "pmi" => compute_pmi_salience(
                domain_count,
                background_count,
                total_domain,
                total_background,
            ),
            "tfidf" => compute_tfidf_salience(domain_count, background_count, total_domain),
            _ => unreachable!(),
        };

        // Filter by minimum salience
        if salience < config.min_salience {
            continue;
        }
        stats.after_salience_filter += 1;

        scored.push(OutputPhrase {
            tokens,
            salience,
            phrase_id: None,  // Will be assigned later if needed
            domain_count,
            background_count,
        });
    }

    // Sort by salience (descending)
    scored.sort_by(|a, b| b.salience.partial_cmp(&a.salience).unwrap());

    Ok((scored, stats))
}

fn compute_ratio_salience(domain_count: u32, background_count: u32) -> f32 {
    domain_count as f32 / (background_count + 1) as f32
}

fn compute_pmi_salience(
    domain_count: u32,
    background_count: u32,
    total_domain: u64,
    total_background: u64,
) -> f32 {
    if background_count == 0 {
        return 10.0; // High salience for phrases not in background
    }

    let p_domain = domain_count as f64 / total_domain as f64;
    let p_background = background_count as f64 / total_background as f64;

    let pmi = (p_domain / p_background).log2();
    pmi as f32
}

fn compute_tfidf_salience(domain_count: u32, background_count: u32, total_domain: u64) -> f32 {
    let tf = domain_count as f32 / total_domain as f32;
    let idf = ((total_domain + 1) as f32 / (background_count + 1) as f32).ln();
    tf * idf
}

fn write_phrases(
    output_path: &str,
    mut phrases: Vec<OutputPhrase>,
    config: &ScoreConfig,
) -> Result<(), Box<dyn std::error::Error>> {
    let file = File::create(output_path)?;
    let mut writer = BufWriter::new(file);

    // Assign phrase IDs if requested
    if config.assign_phrase_ids {
        for (i, phrase) in phrases.iter_mut().enumerate() {
            phrase.phrase_id = Some(config.starting_phrase_id + i as u32);
        }
    }

    let count = phrases.len();
    for phrase in phrases {
        let json = serde_json::to_string(&phrase)?;
        writeln!(writer, "{}", json)?;
    }

    writer.flush()?;
    println!("  ✓ Wrote {} phrases to {}", count, output_path);

    // Print top 10 phrases
    if count > 0 {
        println!("\n🏆 Top phrases by salience:");
        let output_file = File::open(output_path)?;
        let reader = BufReader::new(output_file);
        for (i, line) in reader.lines().enumerate().take(10) {
            let line = line?;
            let phrase: OutputPhrase = serde_json::from_str(&line)?;
            println!(
                "  {}. {} → salience={:.2}, domain={}, background={}",
                i + 1,
                phrase.tokens.join(" "),
                phrase.salience,
                phrase.domain_count,
                phrase.background_count
            );
        }
    }

    Ok(())
}