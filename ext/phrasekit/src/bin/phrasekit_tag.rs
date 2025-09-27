use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::env;
use std::fs::File;
use std::io::{BufRead, BufReader, BufWriter, Write};
use std::path::Path;
use std::process;

#[path = "../payload.rs"]
mod payload;

use payload::Payload;

#[derive(Debug, Deserialize)]
struct TagConfig {
    automaton_path: String,
    payloads_path: String,
    manifest_path: String,
    vocab_path: String,
    #[serde(default = "default_policy")]
    policy: String,
    #[serde(default = "default_max_spans")]
    max_spans: usize,
    #[serde(default = "default_label")]
    label: String,
}

fn default_policy() -> String {
    "leftmost_longest".to_string()
}

fn default_max_spans() -> usize {
    100
}

fn default_label() -> String {
    "PHRASE".to_string()
}

#[derive(Debug, Deserialize)]
struct InputDocument {
    doc_id: String,
    tokens: Vec<String>,
}

#[derive(Debug, Serialize)]
struct OutputDocument {
    doc_id: String,
    tokens: Vec<String>,
    spans: Vec<Span>,
}

#[derive(Debug, Serialize)]
struct Span {
    start: usize,
    end: usize,
    phrase_id: u32,
    label: String,
}

#[derive(Debug, Deserialize)]
struct Vocabulary {
    tokens: HashMap<String, u32>,
    special_tokens: HashMap<String, u32>,
}

#[derive(Debug)]
struct TaggingStats {
    documents: usize,
    total_spans: usize,
    docs_with_spans: usize,
}

fn encode_tokens(tokens: &[String], vocab: &Vocabulary) -> Vec<u32> {
    let unk_id = vocab.special_tokens.get("<UNK>").copied().unwrap_or(0);

    tokens
        .iter()
        .map(|token| {
            let normalized = token.to_lowercase();
            vocab.tokens.get(&normalized).copied().unwrap_or(unk_id)
        })
        .collect()
}

fn tag_corpus(
    corpus_path: &str,
    config: &TagConfig,
    output_path: &str,
) -> Result<TaggingStats, Box<dyn std::error::Error>> {
    println!("🏷️  PhraseKit Corpus Tagging");
    println!("════════════════════════════════════════");
    println!("Corpus:     {}", corpus_path);
    println!("Config:     <config>");
    println!("Output:     {}", output_path);
    println!();

    println!("📚 Loading matcher artifacts...");

    let vocab_data = std::fs::read_to_string(&config.vocab_path)?;
    let vocab: Vocabulary = serde_json::from_str(&vocab_data)?;
    println!("  ✓ Loaded vocabulary ({} tokens)", vocab.tokens.len());

    use daachorse::DoubleArrayAhoCorasick;
    let automaton_bytes = std::fs::read(&config.automaton_path)?;
    let (automaton, _): (DoubleArrayAhoCorasick<u32>, _) = unsafe {
        DoubleArrayAhoCorasick::deserialize_unchecked(&automaton_bytes)
    };
    println!("  ✓ Loaded automaton");

    let payloads_file = File::open(&config.payloads_path)?;
    let payloads_reader = BufReader::new(payloads_file);
    let payloads = payload::load_payloads(payloads_reader)?;
    println!("  ✓ Loaded {} phrase payloads", payloads.len());

    #[derive(Debug, Deserialize)]
    struct Manifest {
        separator_id: u32,
    }

    let manifest_data = std::fs::read_to_string(&config.manifest_path)?;
    let manifest: Manifest = serde_json::from_str(&manifest_data)?;
    println!("  ✓ Loaded manifest");
    println!();

    println!("🔍 Tagging documents...");

    let corpus_file = File::open(corpus_path)?;
    let corpus_reader = BufReader::new(corpus_file);

    let output_file = File::create(output_path)?;
    let mut output_writer = BufWriter::new(output_file);

    let mut stats = TaggingStats {
        documents: 0,
        total_spans: 0,
        docs_with_spans: 0,
    };

    for line in corpus_reader.lines() {
        let line = line?;
        if line.trim().is_empty() {
            continue;
        }

        let doc: InputDocument = serde_json::from_str(&line)?;

        let token_ids = encode_tokens(&doc.tokens, &vocab);

        let separator = manifest.separator_id;
        let mut bytes = Vec::with_capacity(token_ids.len() * 5);
        for &token_id in &token_ids {
            bytes.extend_from_slice(&token_id.to_le_bytes());
            bytes.extend_from_slice(&separator.to_le_bytes());
        }

        #[derive(Debug, Clone, Copy)]
        struct Match {
            start: usize,
            end: usize,
            phrase_id: u32,
        }

        let mut matches: Vec<Match> = automaton
            .find_overlapping_iter(&bytes)
            .filter_map(|m| {
                let pattern_id = m.value() as usize;
                let start_token = m.start() / 8;
                let end_token = (m.end() + 7) / 8;

                payloads.get(pattern_id).map(|payload| Match {
                    start: start_token,
                    end: end_token,
                    phrase_id: payload.phrase_id,
                })
            })
            .collect();

        if config.policy == "leftmost_longest" {
            matches.sort_by_key(|m| (m.start, std::cmp::Reverse(m.end)));

            let mut resolved = Vec::new();
            let mut covered_end = 0;

            for m in matches {
                if m.start >= covered_end {
                    resolved.push(m);
                    covered_end = m.end;
                }
            }

            matches = resolved;
        } else if config.policy == "leftmost_first" {
            matches.sort_by_key(|m| m.start);

            let mut resolved = Vec::new();
            let mut covered_end = 0;

            for m in matches {
                if m.start >= covered_end {
                    resolved.push(m);
                    covered_end = m.end;
                }
            }

            matches = resolved;
        }

        if matches.len() > config.max_spans {
            matches.truncate(config.max_spans);
        }

        let spans: Vec<Span> = matches
            .into_iter()
            .map(|m| Span {
                start: m.start,
                end: m.end,
                phrase_id: m.phrase_id,
                label: config.label.clone(),
            })
            .collect();

        stats.total_spans += spans.len();
        if !spans.is_empty() {
            stats.docs_with_spans += 1;
        }

        let output_doc = OutputDocument {
            doc_id: doc.doc_id,
            tokens: doc.tokens,
            spans,
        };

        serde_json::to_writer(&mut output_writer, &output_doc)?;
        writeln!(&mut output_writer)?;

        stats.documents += 1;

        if stats.documents % 1000 == 0 {
            print!("\r  Processed {} documents...", stats.documents);
            std::io::stdout().flush()?;
        }
    }

    if stats.documents % 1000 != 0 {
        println!("\r  ✓ Processed {} documents", stats.documents);
    } else {
        println!();
        println!("  ✓ Processed {} documents", stats.documents);
    }

    output_writer.flush()?;

    println!();
    println!("✅ Tagging complete!");
    println!();
    println!("📈 Statistics:");
    println!("  Documents:              {}", stats.documents);
    println!("  Total spans:            {}", stats.total_spans);
    println!("  Documents with spans:   {}", stats.docs_with_spans);
    println!(
        "  Avg spans per document: {:.2}",
        if stats.documents > 0 {
            stats.total_spans as f64 / stats.documents as f64
        } else {
            0.0
        }
    );

    Ok(stats)
}

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() != 4 {
        eprintln!("Usage: {} <corpus.jsonl> <config.json> <output.jsonl>", args[0]);
        eprintln!();
        eprintln!("Arguments:");
        eprintln!("  corpus.jsonl  - Input corpus with pre-tokenized documents");
        eprintln!("  config.json   - Tagging configuration");
        eprintln!("  output.jsonl  - Output path for tagged corpus");
        process::exit(1);
    }

    let corpus_path = &args[1];
    let config_path = &args[2];
    let output_path = &args[3];

    if !Path::new(corpus_path).exists() {
        eprintln!("Error: Corpus file not found: {}", corpus_path);
        process::exit(1);
    }

    if !Path::new(config_path).exists() {
        eprintln!("Error: Config file not found: {}", config_path);
        process::exit(1);
    }

    let config_data = match std::fs::read_to_string(config_path) {
        Ok(data) => data,
        Err(e) => {
            eprintln!("Error: Failed to read config file: {}", e);
            process::exit(1);
        }
    };

    let config: TagConfig = match serde_json::from_str(&config_data) {
        Ok(cfg) => cfg,
        Err(e) => {
            eprintln!("Error: Failed to parse config: {}", e);
            process::exit(1);
        }
    };

    if let Err(e) = tag_corpus(corpus_path, &config, output_path) {
        eprintln!("Error: Tagging failed: {}", e);
        process::exit(1);
    }
}