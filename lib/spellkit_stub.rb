# SpellKit stub for integration example
# This will be replaced by the actual spellkit gem (version 0.1.1+)

module SpellKit
  class Error < StandardError; end

  class << self
    attr_reader :stats

    def load!(dictionary:, edit_distance: 1, frequency_threshold: 0, protected_terms: nil, skip_patterns: {})
      @loaded = true
      @edit_distance = edit_distance
      @protected_terms = Set.new(protected_terms || %w[CDK10 IL6 IL-6 BRCA1 BRCA2 TP53 EGFR])
      @stats = {
        version: "spellkit-stub-0.1.1",
        loaded_at: Time.now,
        tokens_corrected: 0,
        p50_us: 20,
        p95_us: 60
      }
      puts "SpellKit loaded (stub implementation)"
    end

    def suggestions(term, max = 5)
      return [] unless @loaded

      # Stub suggestions
      case term.downcase
      when "sequnce"
        [{"term" => "sequence", "distance" => 1, "freq" => 50000}]
      when "helllo"
        [{"term" => "hello", "distance" => 1, "freq" => 100000}]
      when "lyssis"
        [{"term" => "lysis", "distance" => 1, "freq" => 12345}]
      when "protien"
        [{"term" => "protein", "distance" => 1, "freq" => 54321}]
      else
        []
      end
    end

    def correct?(term)
      return false unless @loaded

      # Protected terms are always correct
      return true if @protected_terms.include?(term)

      # Stub: check if term is in "dictionary"
      known_terms = %w[hello world sequence gene the with to need i lysis protein oligo rat buffer western blot]
      known_terms.include?(term.downcase) || @protected_terms.include?(term)
    end

    def correct(term)
      return term unless @loaded

      # Protected terms never get corrected
      return term if @protected_terms.include?(term)

      # Stub corrections
      corrections = {
        "sequnce" => "sequence",
        "helllo" => "hello",
        "lyssis" => "lysis",
        "protien" => "protein"
      }

      corrections[term.downcase] || term
    end

    def correct_tokens(tokens)
      return tokens unless @loaded
      tokens.map { |t| correct(t) }
    end

    def healthcheck
      raise Error, "SpellKit not loaded. Call SpellKit.load! first" unless @loaded
      true
    end
  end
end