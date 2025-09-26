mod manifest;
mod matcher;
mod payload;
mod policy;

use magnus::{define_module, function, method, prelude::*, Error, RArray, RHash, Ruby, Value};
use matcher::{Matcher as RustMatcher, Stats};
use parking_lot::RwLock;
use policy::MatchPolicy;
use std::sync::Arc;

type SharedMatcher = Arc<RwLock<Option<Arc<RustMatcher>>>>;

#[magnus::wrap(class = "PhraseKit::NativeMatcher", free_immediately, size)]
struct MatcherWrapper {
    matcher: SharedMatcher,
}

impl MatcherWrapper {
    fn new() -> Self {
        Self {
            matcher: Arc::new(RwLock::new(None)),
        }
    }

    fn load(&self, automaton_path: String, payloads_path: String, manifest_path: String) -> Result<(), Error> {
        let matcher = RustMatcher::load(&automaton_path, &payloads_path, &manifest_path)
            .map_err(|e| Error::new(magnus::exception::runtime_error(), format!("Failed to load matcher: {}", e)))?;

        let mut guard = self.matcher.write();
        *guard = Some(Arc::new(matcher));

        Ok(())
    }

    fn match_tokens(&self, token_ids: Vec<u32>, policy: String, max: usize) -> Result<RArray, Error> {
        let guard = self.matcher.read();
        let matcher = guard
            .as_ref()
            .ok_or_else(|| Error::new(magnus::exception::runtime_error(), "Matcher not loaded"))?;

        let match_policy = MatchPolicy::from_str(&policy)
            .ok_or_else(|| Error::new(magnus::exception::arg_error(), format!("Invalid policy: {}", policy)))?;

        let matches = matcher.match_tokens(&token_ids, match_policy, max);

        let result = RArray::new();
        for m in matches {
            let hash = RHash::new();
            hash.aset("start", m.start)?;
            hash.aset("end", m.end)?;
            hash.aset("phrase_id", m.payload.phrase_id)?;
            hash.aset("salience", m.payload.salience)?;
            hash.aset("count", m.payload.count)?;
            hash.aset("n", m.payload.n)?;
            result.push(hash)?;
        }

        Ok(result)
    }

    fn stats(&self) -> Result<RHash, Error> {
        let guard = self.matcher.read();
        let matcher = guard
            .as_ref()
            .ok_or_else(|| Error::new(magnus::exception::runtime_error(), "Matcher not loaded"))?;

        let stats = Stats::from_matcher(matcher);
        let hash = RHash::new();

        hash.aset("version", stats.version)?;
        hash.aset("loaded_at", stats.loaded_at.duration_since(std::time::UNIX_EPOCH).unwrap().as_millis() as u64)?;
        hash.aset("num_patterns", stats.num_patterns)?;
        hash.aset("heap_mb", stats.heap_mb)?;
        hash.aset("hits_total", stats.hits_total)?;
        hash.aset("p50_us", stats.p50_us)?;
        hash.aset("p95_us", stats.p95_us)?;
        hash.aset("p99_us", stats.p99_us)?;

        Ok(hash)
    }

    fn healthcheck(&self) -> Result<bool, Error> {
        let guard = self.matcher.read();
        guard
            .as_ref()
            .ok_or_else(|| Error::new(magnus::exception::runtime_error(), "Matcher not loaded"))?;
        Ok(true)
    }
}

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let module = define_module("PhraseKit")?;
    let class = module.define_class("NativeMatcher", ruby.class_object())?;

    class.define_singleton_method("new", function!(MatcherWrapper::new, 0))?;
    class.define_method("load", method!(MatcherWrapper::load, 3))?;
    class.define_method("match_tokens", method!(MatcherWrapper::match_tokens, 3))?;
    class.define_method("stats", method!(MatcherWrapper::stats, 0))?;
    class.define_method("healthcheck", method!(MatcherWrapper::healthcheck, 0))?;

    Ok(())
}