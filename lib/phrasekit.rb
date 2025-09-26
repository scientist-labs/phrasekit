require "phrasekit/version"
require "phrasekit/phrasekit"
require "phrasekit/miner"
require "phrasekit/scorer"

module PhraseKit
  class Error < StandardError; end

  class << self
    attr_reader :vocabulary

    def load!(automaton_path:, payloads_path:, manifest_path:, vocab_path: nil)
      @matcher = NativeMatcher.new
      begin
        @matcher.load(automaton_path.to_s, payloads_path.to_s, manifest_path.to_s)
      rescue RuntimeError => e
        raise Error, e.message
      end

      if vocab_path
        begin
          require "json"
          vocab_data = JSON.parse(File.read(vocab_path))
          @vocabulary = {
            tokens: vocab_data["tokens"],
            special_tokens: vocab_data["special_tokens"],
            separator_id: vocab_data["separator_id"]
          }
        rescue => e
          raise Error, "Failed to load vocabulary: #{e.message}"
        end
      else
        @vocabulary = nil
      end
    end

    def match_tokens(token_ids:, policy: :leftmost_longest, max: 32)
      raise Error, "PhraseKit not loaded. Call PhraseKit.load! first" unless @matcher
      @matcher.match_tokens(token_ids, policy.to_s, max).map(&:symbolize_keys)
    end

    def encode_tokens(tokens)
      raise Error, "Vocabulary not loaded. Call PhraseKit.load! with vocab_path" unless @vocabulary

      unk_id = @vocabulary[:special_tokens]["<UNK>"]
      tokens.map do |token|
        normalized = token.to_s.downcase
        @vocabulary[:tokens][normalized] || unk_id
      end
    end

    def match_text_tokens(tokens:, policy: :leftmost_longest, max: 32)
      raise Error, "PhraseKit not loaded. Call PhraseKit.load! first" unless @matcher
      raise Error, "Vocabulary not loaded. Call PhraseKit.load! with vocab_path" unless @vocabulary

      token_ids = encode_tokens(tokens)
      match_tokens(token_ids: token_ids, policy: policy, max: max)
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