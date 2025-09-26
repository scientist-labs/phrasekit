use crate::manifest::Manifest;
use crate::payload::{load_payloads, Payload};
use crate::policy::{resolve_overlaps, Match, MatchPolicy};
use daachorse::DoubleArrayAhoCorasick;
use std::fs::File;
use std::io::BufReader;
use std::path::Path;
use std::sync::Arc;
use std::time::{Duration, SystemTime};
use thiserror::Error;

#[derive(Error, Debug)]
pub enum MatcherError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Manifest error: {0}")]
    Manifest(#[from] crate::manifest::ManifestError),

    #[error("Automaton error: {0}")]
    Automaton(String),

    #[error("Matcher not loaded")]
    NotLoaded,
}

pub struct Matcher {
    automaton: DoubleArrayAhoCorasick<u32>,
    payloads: Vec<Payload>,
    manifest: Manifest,
    loaded_at: SystemTime,
}

impl Matcher {
    pub fn load<P: AsRef<Path>>(
        automaton_path: P,
        payloads_path: P,
        manifest_path: P,
    ) -> Result<Self, MatcherError> {
        let manifest = Manifest::load(manifest_path)?;

        let automaton_bytes = std::fs::read(automaton_path)?;
        let (automaton, _): (DoubleArrayAhoCorasick<u32>, _) = unsafe {
            DoubleArrayAhoCorasick::deserialize_unchecked(&automaton_bytes)
        };

        let payloads_file = File::open(payloads_path)?;
        let payloads_reader = BufReader::new(payloads_file);
        let payloads = load_payloads(payloads_reader)?;

        if payloads.len() != manifest.num_patterns {
            return Err(MatcherError::Automaton(format!(
                "Payload count mismatch: manifest says {}, got {}",
                manifest.num_patterns,
                payloads.len()
            )));
        }

        Ok(Self {
            automaton,
            payloads,
            manifest,
            loaded_at: SystemTime::now(),
        })
    }

    pub fn match_tokens(
        &self,
        token_ids: &[u32],
        policy: MatchPolicy,
        max: usize,
    ) -> Vec<Match> {
        if token_ids.is_empty() {
            return Vec::new();
        }

        let separator = self.manifest.separator_id;
        let mut bytes = Vec::with_capacity(token_ids.len() * 5);
        for &token_id in token_ids {
            bytes.extend_from_slice(&token_id.to_le_bytes());
            bytes.extend_from_slice(&separator.to_le_bytes());
        }

        let matches: Vec<Match> = self
            .automaton
            .find_overlapping_iter(&bytes)
            .filter_map(|m| {
                let pattern_id = m.value() as usize;
                let start_token = m.start() / 8;
                let end_token = (m.end() + 7) / 8;

                self.payloads
                    .get(pattern_id)
                    .map(|payload| Match::new(start_token, end_token, pattern_id, payload.clone()))
            })
            .collect();

        let mut resolved = resolve_overlaps(matches, policy);

        if resolved.len() > max {
            resolved.truncate(max);
        }

        resolved
    }

    pub fn manifest(&self) -> &Manifest {
        &self.manifest
    }

    pub fn num_patterns(&self) -> usize {
        self.payloads.len()
    }

    pub fn loaded_at(&self) -> SystemTime {
        self.loaded_at
    }

    pub fn memory_usage_mb(&self) -> f64 {
        let automaton_size = std::mem::size_of_val(&self.automaton);
        let payloads_size = self.payloads.len() * std::mem::size_of::<Payload>();
        ((automaton_size + payloads_size) as f64) / 1_048_576.0
    }
}

pub struct Stats {
    pub version: String,
    pub loaded_at: SystemTime,
    pub num_patterns: usize,
    pub heap_mb: f64,
    pub hits_total: u64,
    pub p50_us: u64,
    pub p95_us: u64,
    pub p99_us: u64,
}

impl Stats {
    pub fn from_matcher(matcher: &Matcher) -> Self {
        Self {
            version: matcher.manifest.version.clone(),
            loaded_at: matcher.loaded_at,
            num_patterns: matcher.num_patterns(),
            heap_mb: matcher.memory_usage_mb(),
            hits_total: 0,
            p50_us: 0,
            p95_us: 0,
            p99_us: 0,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::payload::Payload;
    use std::io::Write;
    use tempfile::NamedTempFile;

    fn create_test_artifacts() -> (NamedTempFile, NamedTempFile, NamedTempFile) {
        let patterns = vec![vec![1u32, 2u32], vec![2u32, 3u32]];

        let automaton = DoubleArrayAhoCorasick::new(patterns).unwrap();
        let automaton_bytes = automaton.serialize();

        let mut automaton_file = NamedTempFile::new().unwrap();
        automaton_file.write_all(&automaton_bytes).unwrap();
        automaton_file.flush().unwrap();

        let mut payloads_file = NamedTempFile::new().unwrap();
        let payload1 = Payload::new(100, 1.5, 50, 2);
        let payload2 = Payload::new(200, 2.0, 100, 2);
        payload1.write_to(&mut payloads_file).unwrap();
        payload2.write_to(&mut payloads_file).unwrap();
        payloads_file.flush().unwrap();

        let mut manifest_file = NamedTempFile::new().unwrap();
        let manifest_json = r#"{
            "version": "test-v1",
            "tokenizer": "test-tokenizer",
            "num_patterns": 2,
            "built_at": "2025-01-01T00:00:00Z",
            "separator_id": 4294967294
        }"#;
        manifest_file.write_all(manifest_json.as_bytes()).unwrap();
        manifest_file.flush().unwrap();

        (automaton_file, payloads_file, manifest_file)
    }

    #[test]
    fn test_matcher_load() {
        let (automaton_file, payloads_file, manifest_file) = create_test_artifacts();

        let matcher = Matcher::load(
            automaton_file.path(),
            payloads_file.path(),
            manifest_file.path(),
        )
        .unwrap();

        assert_eq!(matcher.num_patterns(), 2);
        assert_eq!(matcher.manifest().version, "test-v1");
    }

    #[test]
    fn test_matcher_match_tokens() {
        let (automaton_file, payloads_file, manifest_file) = create_test_artifacts();

        let matcher = Matcher::load(
            automaton_file.path(),
            payloads_file.path(),
            manifest_file.path(),
        )
        .unwrap();

        let token_ids = vec![1, 2, 3, 4];
        let matches = matcher.match_tokens(&token_ids, MatchPolicy::LeftmostLongest, 10);

        assert_eq!(matches.len(), 2);
        assert_eq!(matches[0].start, 0);
        assert_eq!(matches[0].end, 2);
        assert_eq!(matches[1].start, 1);
        assert_eq!(matches[1].end, 3);
    }
}