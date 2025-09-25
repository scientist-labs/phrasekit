# SpellKit stub for integration example
# This will be replaced by the actual spellkit gem

module SpellKit
  class Error < StandardError; end

  class << self
    attr_reader :stats

    def load!(unigrams_path:, symbols_path:, cas_path: nil, skus_path: nil, species_path: nil, manifest_path: nil, edit_distance: 1)
      @loaded = true
      @edit_distance = edit_distance
      @stats = {
        version: "spellkit-stub-2025-09-25",
        loaded_at: Time.now,
        tokens_corrected: 0,
        p50_us: 20,
        p95_us: 60
      }
      puts "SpellKit loaded (stub implementation)"
    end

    def suggest(term, max: 5)
      return [] unless @loaded

      # Stub suggestions
      case term.downcase
      when "lyssis"
        [{term: "lysis", distance: 1, freq: 12345}]
      when "protien"
        [{term: "protein", distance: 1, freq: 54321}]
      else
        []
      end
    end

    def correct_if_unknown(term, guard: :domain)
      return term unless @loaded

      # Protected terms (domain guard)
      protected_terms = %w[CDK10 IL6 IL-6 BRCA1 BRCA2 TP53 EGFR]
      return term if protected_terms.include?(term)

      # Stub corrections
      corrections = {
        "lyssis" => "lysis",
        "protien" => "protein",
        "oligo" => "oligo",  # already correct
        "rat" => "rat"       # already correct
      }

      corrections[term] || term
    end

    def correct_tokens(tokens, guard: :domain)
      return tokens unless @loaded
      tokens.map { |t| correct_if_unknown(t, guard: guard) }
    end

    def healthcheck
      raise Error, "SpellKit not loaded. Call SpellKit.load! first" unless @loaded
      true
    end
  end
end