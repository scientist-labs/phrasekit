use daachorse::DoubleArrayAhoCorasick;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs::File;
use std::path::PathBuf;

#[path = "../payload.rs"]
mod payload;

#[path = "../manifest.rs"]
mod manifest;

use manifest::Manifest;
use payload::Payload;

#[derive(Debug, Serialize)]
struct Vocabulary {
    tokens: HashMap<String, u32>,
    special_tokens: HashMap<String, u32>,
    vocab_size: usize,
    separator_id: u32,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().collect();
    let output_dir = if args.len() > 1 {
        PathBuf::from(&args[1])
    } else {
        PathBuf::from("spec/fixtures")
    };

    std::fs::create_dir_all(&output_dir)?;

    println!("Building test fixtures in: {}", output_dir.display());

    // Define test patterns as byte sequences (token_id + separator)
    let separator: u32 = 4294967294;

    // Pattern 0: [100, 101] - "machine learning"
    let pattern0 = encode_tokens(&[100, 101], separator);

    // Pattern 1: [200, 101] - "deep learning"
    let pattern1 = encode_tokens(&[200, 101], separator);

    // Pattern 2: [100, 101, 102] - "machine learning algorithms"
    let pattern2 = encode_tokens(&[100, 101, 102], separator);

    let patterns = vec![pattern0, pattern1, pattern2];
    let num_patterns = patterns.len();

    // Build automaton
    println!("Building automaton with {} patterns", num_patterns);
    let automaton: DoubleArrayAhoCorasick<u32> = DoubleArrayAhoCorasick::new(patterns)
        .map_err(|e| format!("Failed to build automaton: {:?}", e))?;

    // Serialize automaton
    let automaton_bytes = automaton.serialize();
    let automaton_path = output_dir.join("phrases.daac");
    std::fs::write(&automaton_path, &automaton_bytes)?;
    println!("✓ Wrote automaton ({} bytes) to {}", automaton_bytes.len(), automaton_path.display());

    // Create payloads
    let payloads = vec![
        Payload::new(100, 2.5, 150, 2),  // "machine learning" - [100, 101]
        Payload::new(200, 2.0, 100, 2),  // "deep learning" - [200, 101]
        Payload::new(300, 3.0, 200, 3),  // "machine learning algorithms" - [100, 101, 102]
    ];

    // Write payloads
    let payloads_path = output_dir.join("payloads.bin");
    let mut payloads_file = File::create(&payloads_path)?;
    for payload in &payloads {
        payload.write_to(&mut payloads_file)?;
    }
    println!("✓ Wrote {} payloads to {}", payloads.len(), payloads_path.display());

    // Create manifest
    let manifest = Manifest {
        version: "test-v1".to_string(),
        tokenizer: "test-tokenizer".to_string(),
        num_patterns: num_patterns,
        min_count: Some(10),
        salience_threshold: Some(1.0),
        built_at: "2025-09-25T00:00:00Z".to_string(),
        separator_id: separator,
    };

    let manifest_path = output_dir.join("manifest.json");
    let manifest_json = serde_json::to_string_pretty(&manifest)?;
    std::fs::write(&manifest_path, manifest_json)?;
    println!("✓ Wrote manifest to {}", manifest_path.display());

    // Create vocabulary
    let mut tokens = HashMap::new();
    tokens.insert("machine".to_string(), 100);
    tokens.insert("learning".to_string(), 101);
    tokens.insert("algorithms".to_string(), 102);
    tokens.insert("deep".to_string(), 200);

    let mut special_tokens = HashMap::new();
    special_tokens.insert("<UNK>".to_string(), 0);

    let vocabulary = Vocabulary {
        tokens,
        special_tokens,
        vocab_size: 5,
        separator_id: separator,
    };

    let vocab_path = output_dir.join("vocab.json");
    let vocab_json = serde_json::to_string_pretty(&vocabulary)?;
    std::fs::write(&vocab_path, vocab_json)?;
    println!("✓ Wrote vocabulary to {}", vocab_path.display());

    println!("\n✅ Test fixtures generated successfully!");
    println!("\nTest patterns:");
    println!("  Pattern 0: tokens [100, 101] → phrase_id 100 (salience 2.5) - 'machine learning'");
    println!("  Pattern 1: tokens [200, 101] → phrase_id 200 (salience 2.0) - 'deep learning'");
    println!("  Pattern 2: tokens [100, 101, 102] → phrase_id 300 (salience 3.0) - 'machine learning algorithms'");

    Ok(())
}

fn encode_tokens(tokens: &[u32], separator: u32) -> Vec<u8> {
    let mut bytes = Vec::new();
    for &token in tokens {
        bytes.extend_from_slice(&token.to_le_bytes());
        bytes.extend_from_slice(&separator.to_le_bytes());
    }
    bytes
}