require "phrasekit/version"

module PhraseKit
  begin
    require "phrasekit/phrasekit"
    NATIVE_EXTENSION_LOADED = true
  rescue LoadError
    NATIVE_EXTENSION_LOADED = false
  end

  class Error < StandardError; end

  class << self
    def load!(automaton_path:, payloads_path:, manifest_path:)
      if NATIVE_EXTENSION_LOADED
        @matcher = NativeMatcher.new
        @matcher.load(automaton_path.to_s, payloads_path.to_s, manifest_path.to_s)
      else
        @loaded = true
        @stats_data = {
          version: VERSION,
          loaded_at: Time.now.to_i,
          num_patterns: 0,
          heap_mb: 0,
          hits_total: 0,
          p50_us: 50,
          p95_us: 200,
          p99_us: 300
        }
        puts "PhraseKit loaded (Ruby stub - native extension not available)"
      end
    end

    def match_tokens(token_ids:, policy: :leftmost_longest, max: 32)
      if NATIVE_EXTENSION_LOADED
        raise Error, "PhraseKit not loaded. Call PhraseKit.load! first" unless @matcher
        @matcher.match_tokens(token_ids, policy.to_s, max).map(&:symbolize_keys)
      else
        raise Error, "PhraseKit not loaded. Call PhraseKit.load! first" unless @loaded
        []
      end
    end

    def match_text(text, policy: :leftmost_longest, max: 32)
      raise Error, "Text-based matching requires a tokenizer adapter (not yet implemented)"
    end

    def stats
      if NATIVE_EXTENSION_LOADED
        raise Error, "PhraseKit not loaded. Call PhraseKit.load! first" unless @matcher
        stats_hash = @matcher.stats
        stats_hash[:loaded_at] = Time.at(stats_hash[:loaded_at])
        stats_hash
      else
        raise Error, "PhraseKit not loaded. Call PhraseKit.load! first" unless @loaded
        @stats_data.merge(loaded_at: Time.at(@stats_data[:loaded_at]))
      end
    end

    def healthcheck
      if NATIVE_EXTENSION_LOADED
        raise Error, "PhraseKit not loaded. Call PhraseKit.load! first" unless @matcher
        @matcher.healthcheck
      else
        raise Error, "PhraseKit not loaded. Call PhraseKit.load! first" unless @loaded
        true
      end
    end

    def hello
      if NATIVE_EXTENSION_LOADED
        (@matcher || NativeMatcher.new).hello
      else
        "Hello from PhraseKit! (Ruby stub version #{VERSION})"
      end
    end
  end
end

class Hash
  def symbolize_keys
    transform_keys { |key| key.to_sym rescue key }
  end unless method_defined?(:symbolize_keys)
end