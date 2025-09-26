require "spec_helper"
require "phrasekit"

RSpec.describe PhraseKit do
  describe "module constants" do
    it "has a version number" do
      expect(PhraseKit::VERSION).not_to be nil
      expect(PhraseKit::VERSION).to match(/^\d+\.\d+\.\d+$/)
    end
  end

  describe ".load!" do
    let(:test_paths) do
      {
        automaton_path: "spec/fixtures/phrases.daac",
        payloads_path: "spec/fixtures/payloads.bin",
        manifest_path: "spec/fixtures/manifest.json"
      }
    end

    it "accepts required paths" do
      expect { PhraseKit.load!(**test_paths) }.not_to raise_error
    end

    it "sets loaded state" do
      PhraseKit.load!(**test_paths)
      expect { PhraseKit.healthcheck }.not_to raise_error
    end
  end

  describe ".match_tokens" do
    before do
      PhraseKit.load!(
        automaton_path: "spec/fixtures/phrases.daac",
        payloads_path: "spec/fixtures/payloads.bin",
        manifest_path: "spec/fixtures/manifest.json"
      )
    end

    it "requires token_ids parameter" do
      expect { PhraseKit.match_tokens(token_ids: []) }.not_to raise_error
    end

    it "accepts policy parameter" do
      [:leftmost_longest, :leftmost_first, :salience_max].each do |policy|
        result = PhraseKit.match_tokens(token_ids: [1, 2, 3], policy: policy)
        expect(result).to be_an(Array)
      end
    end

    it "accepts max parameter" do
      result = PhraseKit.match_tokens(token_ids: [1, 2, 3], max: 10)
      expect(result).to be_an(Array)
    end

    it "returns array of matches" do
      result = PhraseKit.match_tokens(token_ids: [1, 2, 3])
      expect(result).to be_an(Array)
      expect(result.length).to be >= 0
    end

    describe "basic matching" do
      it "finds exact phrase matches" do
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
        token_ids = [100, 101, 50, 200, 101]
        matches = PhraseKit.match_tokens(token_ids: token_ids)

        expect(matches.length).to eq(2)
        expect(matches[0][:end]).to be <= matches[1][:start]
      end
    end

    describe "matching policies" do
      let(:overlapping_tokens) { [100, 101, 102] }

      it "applies leftmost_longest policy" do
        matches = PhraseKit.match_tokens(
          token_ids: overlapping_tokens,
          policy: :leftmost_longest
        )

        expect(matches.first[:n]).to eq(3)
      end

      it "applies leftmost_first policy" do
        matches = PhraseKit.match_tokens(
          token_ids: overlapping_tokens,
          policy: :leftmost_first
        )

        expect(matches).not_to be_empty
      end

      it "applies salience_max policy" do
        matches = PhraseKit.match_tokens(
          token_ids: overlapping_tokens,
          policy: :salience_max
        )

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
        token_ids = (100..120).to_a
        matches = PhraseKit.match_tokens(token_ids: token_ids, max: 5)
        expect(matches.length).to be <= 5
      end
    end
  end

  describe ".stats" do
    context "when not loaded" do
      before { PhraseKit.instance_variable_set(:@matcher, nil) }

      it "raises error" do
        expect { PhraseKit.stats }.to raise_error(PhraseKit::Error, /not loaded/)
      end
    end

    context "when loaded" do
      before do
        PhraseKit.load!(
          automaton_path: "spec/fixtures/phrases.daac",
          payloads_path: "spec/fixtures/payloads.bin",
          manifest_path: "spec/fixtures/manifest.json"
        )
      end

      it "returns stats hash" do
        stats = PhraseKit.stats
        expect(stats).to be_a(Hash)
        expect(stats).to include(
          :version,
          :loaded_at,
          :num_patterns,
          :heap_mb,
          :p50_us,
          :p95_us
        )
      end

      it "includes manifest version" do
        stats = PhraseKit.stats
        expect(stats[:version]).not_to be_nil
      end
    end
  end

  describe ".healthcheck" do
    context "when not loaded" do
      before { PhraseKit.instance_variable_set(:@matcher, nil) }

      it "raises error" do
        expect { PhraseKit.healthcheck }.to raise_error(PhraseKit::Error)
      end
    end

    context "when loaded" do
      before do
        PhraseKit.load!(
          automaton_path: "spec/fixtures/phrases.daac",
          payloads_path: "spec/fixtures/payloads.bin",
          manifest_path: "spec/fixtures/manifest.json"
        )
      end

      it "returns true" do
        expect(PhraseKit.healthcheck).to be true
      end
    end
  end

  describe "performance" do
    before do
      PhraseKit.load!(
        automaton_path: "spec/fixtures/phrases.daac",
        payloads_path: "spec/fixtures/payloads.bin",
        manifest_path: "spec/fixtures/manifest.json"
      )
    end

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

      expect(results.uniq.length).to eq(1)
    end
  end

  describe "hot reload" do
    before do
      PhraseKit.load!(
        automaton_path: "spec/fixtures/phrases.daac",
        payloads_path: "spec/fixtures/payloads.bin",
        manifest_path: "spec/fixtures/manifest.json"
      )
    end

    it "supports artifact reloading without restart" do
      initial_stats = PhraseKit.stats

      sleep 0.001

      PhraseKit.load!(
        automaton_path: "spec/fixtures/phrases.daac",
        payloads_path: "spec/fixtures/payloads.bin",
        manifest_path: "spec/fixtures/manifest.json"
      )

      new_stats = PhraseKit.stats
      expect(new_stats[:loaded_at]).to be > initial_stats[:loaded_at]
    end
  end

  describe "vocabulary support" do
    let(:test_paths_with_vocab) do
      {
        automaton_path: "spec/fixtures/phrases.daac",
        payloads_path: "spec/fixtures/payloads.bin",
        manifest_path: "spec/fixtures/manifest.json",
        vocab_path: "spec/fixtures/vocab.json"
      }
    end

    describe ".load! with vocab_path" do
      it "loads vocabulary successfully" do
        expect { PhraseKit.load!(**test_paths_with_vocab) }.not_to raise_error
      end

      it "makes vocabulary accessible" do
        PhraseKit.load!(**test_paths_with_vocab)
        expect(PhraseKit.vocabulary).not_to be_nil
        expect(PhraseKit.vocabulary[:tokens]).to be_a(Hash)
        expect(PhraseKit.vocabulary[:special_tokens]).to be_a(Hash)
      end

      it "vocabulary contains expected tokens" do
        PhraseKit.load!(**test_paths_with_vocab)
        vocab = PhraseKit.vocabulary
        expect(vocab[:tokens]["machine"]).to eq(100)
        expect(vocab[:tokens]["learning"]).to eq(101)
        expect(vocab[:tokens]["deep"]).to eq(200)
        expect(vocab[:special_tokens]["<UNK>"]).to eq(0)
      end
    end

    describe ".encode_tokens" do
      before do
        PhraseKit.load!(**test_paths_with_vocab)
      end

      it "encodes known tokens" do
        tokens = ["machine", "learning"]
        result = PhraseKit.encode_tokens(tokens)
        expect(result).to eq([100, 101])
      end

      it "handles unknown tokens with <UNK> ID" do
        tokens = ["machine", "unknown", "learning"]
        result = PhraseKit.encode_tokens(tokens)
        expect(result).to eq([100, 0, 101])
      end

      it "normalizes to lowercase" do
        tokens = ["MACHINE", "Learning", "dEEp"]
        result = PhraseKit.encode_tokens(tokens)
        expect(result).to eq([100, 101, 200])
      end

      it "raises error when vocabulary not loaded" do
        PhraseKit.instance_variable_set(:@vocabulary, nil)
        expect {
          PhraseKit.encode_tokens(["machine"])
        }.to raise_error(PhraseKit::Error, /Vocabulary not loaded/)
      end
    end

    describe ".match_text_tokens" do
      before do
        PhraseKit.load!(**test_paths_with_vocab)
      end

      it "matches phrases from text tokens" do
        tokens = ["machine", "learning"]
        matches = PhraseKit.match_text_tokens(tokens: tokens)
        expect(matches).not_to be_empty
        expect(matches.first[:phrase_id]).to eq(100)
      end

      it "matches longer phrases" do
        tokens = ["machine", "learning", "algorithms"]
        matches = PhraseKit.match_text_tokens(tokens: tokens, policy: :leftmost_longest)
        expect(matches).not_to be_empty
        expect(matches.first[:phrase_id]).to eq(300)
        expect(matches.first[:end]).to eq(3)
      end

      it "handles case insensitivity" do
        tokens = ["DEEP", "Learning"]
        matches = PhraseKit.match_text_tokens(tokens: tokens)
        expect(matches).not_to be_empty
        expect(matches.first[:phrase_id]).to eq(200)
      end

      it "returns empty array for unknown tokens" do
        tokens = ["unknown", "tokens"]
        matches = PhraseKit.match_text_tokens(tokens: tokens)
        expect(matches).to be_empty
      end

      it "raises error when vocabulary not loaded" do
        PhraseKit.instance_variable_set(:@vocabulary, nil)
        expect {
          PhraseKit.match_text_tokens(tokens: ["machine"])
        }.to raise_error(PhraseKit::Error, /Vocabulary not loaded/)
      end
    end

    describe "backwards compatibility" do
      it "load! works without vocab_path" do
        PhraseKit.load!(
          automaton_path: "spec/fixtures/phrases.daac",
          payloads_path: "spec/fixtures/payloads.bin",
          manifest_path: "spec/fixtures/manifest.json"
        )
        expect(PhraseKit.vocabulary).to be_nil
        expect {
          PhraseKit.match_tokens(token_ids: [100, 101])
        }.not_to raise_error
      end
    end
  end
end