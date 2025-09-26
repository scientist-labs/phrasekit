use serde::{Deserialize, Serialize};
use std::fs::File;
use std::io::BufReader;
use std::path::Path;
use thiserror::Error;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Manifest {
    pub version: String,
    pub tokenizer: String,
    pub num_patterns: usize,
    pub min_count: Option<u32>,
    pub salience_threshold: Option<f32>,
    pub built_at: String,
    pub separator_id: u32,
}

#[derive(Error, Debug)]
pub enum ManifestError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("JSON parse error: {0}")]
    Json(#[from] serde_json::Error),

    #[error("Invalid manifest: {0}")]
    Invalid(String),
}

impl Manifest {
    pub fn load<P: AsRef<Path>>(path: P) -> Result<Self, ManifestError> {
        let file = File::open(path)?;
        let reader = BufReader::new(file);
        let manifest: Manifest = serde_json::from_reader(reader)?;

        if manifest.separator_id == 0 {
            return Err(ManifestError::Invalid(
                "separator_id must be non-zero".to_string(),
            ));
        }

        Ok(manifest)
    }

    pub fn validate_compatible(&self, other: &Manifest) -> Result<(), ManifestError> {
        if self.tokenizer != other.tokenizer {
            return Err(ManifestError::Invalid(format!(
                "Tokenizer mismatch: expected {}, got {}",
                self.tokenizer, other.tokenizer
            )));
        }

        if self.separator_id != other.separator_id {
            return Err(ManifestError::Invalid(format!(
                "Separator ID mismatch: expected {}, got {}",
                self.separator_id, other.separator_id
            )));
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_manifest_deserialize() {
        let json = r#"{
            "version": "pk-2025-09-25-01",
            "tokenizer": "scientist-v1",
            "num_patterns": 1287345,
            "min_count": 20,
            "salience_threshold": 1.0,
            "built_at": "2025-09-25T18:44:00Z",
            "separator_id": 4294967294
        }"#;

        let manifest: Manifest = serde_json::from_str(json).unwrap();
        assert_eq!(manifest.version, "pk-2025-09-25-01");
        assert_eq!(manifest.tokenizer, "scientist-v1");
        assert_eq!(manifest.num_patterns, 1287345);
        assert_eq!(manifest.separator_id, 4294967294);
    }
}