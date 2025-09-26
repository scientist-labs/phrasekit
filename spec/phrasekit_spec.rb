require "spec_helper"
require "phrasekit"

RSpec.describe PhraseKit do
  describe "module constants" do
    it "has a version number" do
      expect(PhraseKit::VERSION).not_to be nil
      expect(PhraseKit::VERSION).to match(/^\d+\.\d+\.\d+$/)
    end

    it "indicates native extension status" do
      expect(PhraseKit::NATIVE_EXTENSION_LOADED).to be(true).or be(false)
    end
  end

  describe ".hello" do
    it "returns greeting" do
      greeting = PhraseKit.hello
      expect(greeting).to include("PhraseKit")

      if PhraseKit::NATIVE_EXTENSION_LOADED
        expect(greeting).to include("native extension")
      else
        expect(greeting).to include("Ruby stub")
      end
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
end