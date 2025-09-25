require "phrasekit/version"

module PhraseKit
  class Error < StandardError; end

  class << self
    attr_reader :stats

    def load!(automaton_path:, payloads_path:, manifest_path:)
      @loaded = true
      @stats = {
        version: VERSION,
        loaded_at: Time.now,
        num_patterns: 0,
        heap_mb: 0,
        hits_total: 0,
        p50_us: 50,
        p95_us: 200
      }
      puts "PhraseKit loaded (Ruby stub for M0 - will be replaced with Rust/Magnus in M1)"
    end

    def match_tokens(token_ids:, policy: :leftmost_longest, max: 32)
      raise Error, "PhraseKit not loaded. Call PhraseKit.load! first" unless @loaded

      # Stub matches for demonstration
      # In M1, this will use daachorse for real matching
      []
    end

    def match_text(text, policy: :leftmost_longest, max: 32)
      raise Error, "PhraseKit not loaded. Call PhraseKit.load! first" unless @loaded

      # Stub for text-based matching (requires tokenizer)
      []
    end

    def stats
      raise Error, "PhraseKit not loaded. Call PhraseKit.load! first" unless @loaded
      @stats
    end

    def healthcheck
      raise Error, "PhraseKit not loaded. Call PhraseKit.load! first" unless @loaded
      true
    end

    def hello
      "Hello from PhraseKit! (Ruby stub version #{VERSION})"
    end
  end
end
