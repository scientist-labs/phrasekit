use daachorse::DoubleArrayAhoCorasick;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::fs::File;
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};

#[path = "../payload.rs"]
mod payload;

#[path = "../manifest.rs"]
mod manifest;

use manifest::Manifest;
use payload::Payload;

#[derive(Debug, Deserialize)]
struct PhraseInput {
    tokens: Vec<String>,
    phrase_id: u32,
    salience: f32,
    count: u32,
}

struct ProcessedPhrase {
    token_ids: Vec<u32>,
    phrase_id: u32,
    salience: f32,
    count: u32,
    length: u8,
}

#[derive(Debug, Deserialize)]
struct BuildConfig {
    version: String,
    tokenizer: String,
    separator_id: u32,
    #[serde(default)]
    min_count: Option<u32>,
    #[serde(default)]
    salience_threshold: Option<f32>,
}

#[derive(Debug)]
struct BuildStats {
    total_input: usize,
    filtered_low_count: usize,
    filtered_low_salience: usize,
    duplicate_phrase_ids: usize,
    invalid_tokens: usize,
    built: usize,
}

#[derive(Debug, Serialize)]
struct Vocabulary {
    tokens: HashMap<String, u32>,
    special_tokens: HashMap<String, u32>,
    vocab_size: usize,
    separator_id: u32,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().collect();

    if args.len() < 4 {
        eprintln!("Usage: phrasekit_build <input.jsonl> <config.json> <output_dir>");
        eprintln!("\nExample:");
        eprintln!("  phrasekit_build phrases.jsonl config.json ./artifacts/");
        std::process::exit(1);
    }

    let input_path = &args[1];
    let config_path = &args[2];
    let output_dir = PathBuf::from(&args[3]);

    println!("📦 PhraseKit Artifact Builder");
    println!("════════════════════════════════════════");
    println!("Input:  {}", input_path);
    println!("Config: {}", config_path);
    println!("Output: {}", output_dir.display());
    println!();

    // Load config
    let config = load_config(config_path)?;
    println!("✓ Loaded config: {} (tokenizer: {})", config.version, config.tokenizer);

    // Create output directory
    std::fs::create_dir_all(&output_dir)?;

    // Load and validate phrases
    let (text_phrases, stats, unique_tokens) = load_and_validate_phrases(input_path, &config)?;

    println!("\n📊 Build Statistics:");
    println!("  Total input phrases:     {}", stats.total_input);
    if stats.filtered_low_count > 0 {
        println!("  Filtered (low count):    {}", stats.filtered_low_count);
    }
    if stats.filtered_low_salience > 0 {
        println!("  Filtered (low salience): {}", stats.filtered_low_salience);
    }
    if stats.duplicate_phrase_ids > 0 {
        println!("  Skipped (duplicate IDs): {}", stats.duplicate_phrase_ids);
    }
    if stats.invalid_tokens > 0 {
        println!("  Skipped (invalid tokens): {}", stats.invalid_tokens);
    }
    println!("  Built patterns:          {}", stats.built);

    if text_phrases.is_empty() {
        return Err("No valid phrases to build".into());
    }

    // Build vocabulary and assign token IDs
    println!("\n📚 Building vocabulary...");
    let vocabulary = build_vocabulary(unique_tokens, config.separator_id);
    println!("  ✓ Built vocabulary ({} tokens)", vocabulary.vocab_size);

    // Convert text tokens to IDs
    let mut phrases: Vec<ProcessedPhrase> = Vec::new();
    for phrase in text_phrases {
        let token_ids: Vec<u32> = phrase.tokens.iter()
            .map(|t| *vocabulary.tokens.get(&t.to_lowercase()).unwrap_or(&0))
            .collect();

        phrases.push(ProcessedPhrase {
            token_ids,
            phrase_id: phrase.phrase_id,
            salience: phrase.salience,
            count: phrase.count,
            length: phrase.tokens.len() as u8,
        });
    }

    // Build automaton
    println!("\n🔨 Building automaton...");
    let patterns: Vec<Vec<u8>> = phrases.iter()
        .map(|p| encode_tokens(&p.token_ids, config.separator_id))
        .collect();

    let automaton: DoubleArrayAhoCorasick<u32> = DoubleArrayAhoCorasick::new(patterns)
        .map_err(|e| format!("Failed to build automaton: {:?}", e))?;

    let automaton_bytes = automaton.serialize();
    let automaton_path = output_dir.join("phrases.daac");
    std::fs::write(&automaton_path, &automaton_bytes)?;
    println!("  ✓ Wrote automaton ({} bytes) to {}", automaton_bytes.len(), automaton_path.display());

    // Write payloads
    println!("\n💾 Writing payloads...");
    let payloads: Vec<Payload> = phrases.iter()
        .map(|p| Payload::new(p.phrase_id, p.salience, p.count, p.length))
        .collect();

    let payloads_path = output_dir.join("payloads.bin");
    let mut payloads_file = File::create(&payloads_path)?;
    for payload in &payloads {
        payload.write_to(&mut payloads_file)?;
    }
    let payloads_size = payloads.len() * 17;
    println!("  ✓ Wrote {} payloads ({} bytes) to {}", payloads.len(), payloads_size, payloads_path.display());

    // Generate manifest with checksums
    println!("\n📝 Generating manifest...");
    let manifest = Manifest {
        version: config.version.clone(),
        tokenizer: config.tokenizer.clone(),
        num_patterns: phrases.len(),
        min_count: config.min_count,
        salience_threshold: config.salience_threshold,
        built_at: chrono::Utc::now().to_rfc3339(),
        separator_id: config.separator_id,
    };

    let manifest_path = output_dir.join("manifest.json");
    let manifest_json = serde_json::to_string_pretty(&manifest)?;
    std::fs::write(&manifest_path, manifest_json)?;
    println!("  ✓ Wrote manifest to {}", manifest_path.display());

    // Write vocabulary
    println!("\n💾 Writing vocabulary...");
    let vocab_path = output_dir.join("vocab.json");
    let vocab_json = serde_json::to_string_pretty(&vocabulary)?;
    std::fs::write(&vocab_path, vocab_json)?;
    println!("  ✓ Wrote vocabulary ({} tokens) to {}", vocabulary.vocab_size, vocab_path.display());

    // Summary
    println!("\n✅ Build complete!");
    println!("\nArtifacts:");
    println!("  {} ({} bytes)", automaton_path.display(), automaton_bytes.len());
    println!("  {} ({} bytes)", payloads_path.display(), payloads_size);
    println!("  {}", manifest_path.display());
    println!("  {}", vocab_path.display());

    println!("\n🚀 To use in PhraseKit:");
    println!("  PhraseKit.load!(");
    println!("    automaton_path: {:?},", automaton_path.to_str().unwrap());
    println!("    payloads_path: {:?},", payloads_path.to_str().unwrap());
    println!("    manifest_path: {:?},", manifest_path.to_str().unwrap());
    println!("    vocab_path: {:?}", vocab_path.to_str().unwrap());
    println!("  )");

    Ok(())
}

fn load_config(path: &str) -> Result<BuildConfig, Box<dyn std::error::Error>> {
    let file = File::open(path)?;
    let config: BuildConfig = serde_json::from_reader(file)?;
    Ok(config)
}

fn load_and_validate_phrases(
    path: &str,
    config: &BuildConfig,
) -> Result<(Vec<PhraseInput>, BuildStats, HashSet<String>), Box<dyn std::error::Error>> {
    let file = File::open(path)?;
    let reader = BufReader::new(file);

    let mut phrases = Vec::new();
    let mut seen_ids = HashSet::new();
    let mut unique_tokens: HashSet<String> = HashSet::new();
    let mut stats = BuildStats {
        total_input: 0,
        filtered_low_count: 0,
        filtered_low_salience: 0,
        duplicate_phrase_ids: 0,
        invalid_tokens: 0,
        built: 0,
    };

    println!("\n📖 Loading phrases...");

    for (line_num, line) in reader.lines().enumerate() {
        let line = line?;
        stats.total_input += 1;

        let phrase: PhraseInput = match serde_json::from_str(&line) {
            Ok(p) => p,
            Err(e) => {
                eprintln!("⚠️  Line {}: Failed to parse: {}", line_num + 1, e);
                continue;
            }
        };

        // Validate
        if let Some(min_count) = config.min_count {
            if phrase.count < min_count {
                stats.filtered_low_count += 1;
                continue;
            }
        }

        if let Some(threshold) = config.salience_threshold {
            if phrase.salience < threshold {
                stats.filtered_low_salience += 1;
                continue;
            }
        }

        if phrase.tokens.is_empty() {
            eprintln!("⚠️  Line {}: Empty token sequence", line_num + 1);
            stats.invalid_tokens += 1;
            continue;
        }

        for token in &phrase.tokens {
            if token.is_empty() {
                eprintln!("⚠️  Line {}: Empty token", line_num + 1);
                stats.invalid_tokens += 1;
                continue;
            }
        }

        if !seen_ids.insert(phrase.phrase_id) {
            eprintln!("⚠️  Line {}: Duplicate phrase_id {}", line_num + 1, phrase.phrase_id);
            stats.duplicate_phrase_ids += 1;
            continue;
        }

        for token in &phrase.tokens {
            unique_tokens.insert(token.to_lowercase());
        }

        phrases.push(phrase);
        stats.built += 1;

        if stats.total_input % 10000 == 0 {
            println!("  Processed {} lines...", stats.total_input);
        }
    }

    println!("  ✓ Loaded {} phrases", stats.total_input);

    Ok((phrases, stats, unique_tokens))
}

fn encode_tokens(tokens: &[u32], separator: u32) -> Vec<u8> {
    let mut bytes = Vec::new();
    for &token in tokens {
        bytes.extend_from_slice(&token.to_le_bytes());
        bytes.extend_from_slice(&separator.to_le_bytes());
    }
    bytes
}

fn build_vocabulary(unique_tokens: HashSet<String>, separator_id: u32) -> Vocabulary {
    let mut tokens = HashMap::new();
    let mut sorted_tokens: Vec<String> = unique_tokens.into_iter().collect();
    sorted_tokens.sort();

    for (idx, token) in sorted_tokens.iter().enumerate() {
        tokens.insert(token.clone(), (idx + 1) as u32);
    }

    let mut special_tokens = HashMap::new();
    special_tokens.insert("<UNK>".to_string(), 0);

    let vocab_size = tokens.len() + special_tokens.len();

    Vocabulary {
        tokens,
        special_tokens,
        vocab_size,
        separator_id,
    }
}