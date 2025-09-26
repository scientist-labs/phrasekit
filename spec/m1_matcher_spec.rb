# Spec for M1 implementation validation
# These specs will fail with M0 stub but should pass with M1 real implementation

require "spec_helper"
require "phrasekit"

RSpec.describe "M1: PhraseKit Core Matching" do
  # Skip these tests in M0 (stub implementation)
  before(:all) do
    skip "M1 implementation not yet complete" unless ENV["TEST_M1"]
  end

  before(:each) do
    # In M1, these will be real test fixtures with actual daachorse data
    PhraseKit.load!(
      automaton_path: "spec/fixtures/phrases.daac",
      payloads_path: "spec/fixtures/payloads.bin",
      manifest_path: "spec/fixtures/manifest.json"
    )
  end

  describe "basic matching" do
    it "finds exact phrase matches" do
      # Token IDs for "machine learning"
      token_ids = [100, 101]
      matches = PhraseKit.match_tokens(token_ids: token_ids)

      expect(matches).not_to be_empty
      expect(matches.first).to include(
        start: 0,
        end: 2,
        phrase_id: Integer,
        salience: Float,
        count: Integer,
        n: 2
      )
    end

    it "finds multiple non-overlapping phrases" do
      # "machine learning and deep learning"
      token_ids = [100, 101, 50, 200, 101]
      matches = PhraseKit.match_tokens(token_ids: token_ids)

      expect(matches.length).to eq(2)
      expect(matches[0][:end]).to be <= matches[1][:start]
    end
  end

  describe "matching policies" do
    let(:overlapping_tokens) { [100, 101, 102] }  # "machine learning algorithms"

    it "applies leftmost_longest policy" do
      matches = PhraseKit.match_tokens(
        token_ids: overlapping_tokens,
        policy: :leftmost_longest
      )

      # Should prefer "machine learning algorithms" over "machine learning"
      expect(matches.first[:n]).to eq(3)
    end

    it "applies leftmost_first policy" do
      matches = PhraseKit.match_tokens(
        token_ids: overlapping_tokens,
        policy: :leftmost_first
      )

      # Should return first match found
      expect(matches).not_to be_empty
    end

    it "applies salience_max policy" do
      matches = PhraseKit.match_tokens(
        token_ids: overlapping_tokens,
        policy: :salience_max
      )

      # Should prefer highest salience match
      expect(matches).not_to be_empty
      if matches.length > 1
        expect(matches[0][:salience]).to be >= matches[1][:salience]
      end
    end
  end

  describe "edge cases" do
    it "handles empty input" do
      matches = PhraseKit.match_tokens(token_ids: [])
      expect(matches).to eq([])
    end

    it "handles single token" do
      matches = PhraseKit.match_tokens(token_ids: [100])
      expect(matches).to be_an(Array)
    end

    it "handles unknown tokens" do
      matches = PhraseKit.match_tokens(token_ids: [999999, 888888])
      expect(matches).to eq([])
    end

    it "respects max parameter" do
      token_ids = (100..120).to_a  # Many potential matches
      matches = PhraseKit.match_tokens(token_ids: token_ids, max: 5)
      expect(matches.length).to be <= 5
    end
  end

  describe "performance" do
    it "matches 20-token query in < 500µs (p95 target)" do
      token_ids = (100..119).to_a

      times = 100.times.map do
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
        PhraseKit.match_tokens(token_ids: token_ids)
        Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond) - start
      end

      p95 = times.sort[94]
      expect(p95).to be < 500
    end

    it "handles concurrent matching (thread-safe)" do
      results = 10.times.map do
        Thread.new do
          PhraseKit.match_tokens(token_ids: [100, 101, 102])
        end
      end.map(&:value)

      # All results should be identical
      expect(results.uniq.length).to eq(1)
    end
  end

  describe "hot reload" do
    it "supports artifact reloading without restart" do
      initial_stats = PhraseKit.stats

      # Reload with same files (simulating hot reload)
      PhraseKit.load!(
        automaton_path: "spec/fixtures/phrases.daac",
        payloads_path: "spec/fixtures/payloads.bin",
        manifest_path: "spec/fixtures/manifest.json"
      )

      new_stats = PhraseKit.stats
      expect(new_stats[:loaded_at]).to be > initial_stats[:loaded_at]
    end
  end

  describe "manifest validation" do
    it "validates tokenizer version" do
      # In M1, this should actually check the manifest
      stats = PhraseKit.stats
      expect(stats[:version]).not_to be_nil
    end
  end
end