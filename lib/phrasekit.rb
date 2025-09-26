require "phrasekit/version"
require "phrasekit/phrasekit"

module PhraseKit
  class Error < StandardError; end

  class << self
    def load!(automaton_path:, payloads_path:, manifest_path:)
      @matcher = NativeMatcher.new
      begin
        @matcher.load(automaton_path.to_s, payloads_path.to_s, manifest_path.to_s)
      rescue RuntimeError => e
        raise Error, e.message
      end
    end

    def match_tokens(token_ids:, policy: :leftmost_longest, max: 32)
      raise Error, "PhraseKit not loaded. Call PhraseKit.load! first" unless @matcher
      @matcher.match_tokens(token_ids, policy.to_s, max).map(&:symbolize_keys)
    end

    def match_text(text, policy: :leftmost_longest, max: 32)
      raise Error, "Text-based matching requires a tokenizer adapter (not yet implemented)"
    end

    def stats
      raise Error, "PhraseKit not loaded. Call PhraseKit.load! first" unless @matcher
      begin
        stats_hash = @matcher.stats.symbolize_keys
        stats_hash[:loaded_at] = Time.at(stats_hash[:loaded_at] / 1000.0)
        stats_hash
      rescue RuntimeError => e
        raise Error, e.message
      end
    end

    def healthcheck
      raise Error, "PhraseKit not loaded. Call PhraseKit.load! first" unless @matcher
      begin
        @matcher.healthcheck
      rescue RuntimeError => e
        raise Error, e.message
      end
    end
  end
end

class Hash
  def symbolize_keys
    transform_keys { |key| key.to_sym rescue key }
  end unless method_defined?(:symbolize_keys)
end