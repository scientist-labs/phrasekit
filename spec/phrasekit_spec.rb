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
        automaton_path: "spec/fixtures/test.daac",
        payloads_path: "spec/fixtures/test.bin",
        manifest_path: "spec/fixtures/test.json"
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
        automaton_path: "spec/fixtures/test.daac",
        payloads_path: "spec/fixtures/test.bin",
        manifest_path: "spec/fixtures/test.json"
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

    it "returns array of matches (stub returns empty)" do
      result = PhraseKit.match_tokens(token_ids: [1, 2, 3])
      expect(result).to be_an(Array)
      # In M0 stub, this is empty
      expect(result).to eq([])
    end
  end

  describe ".stats" do
    context "when not loaded" do
      before { PhraseKit.instance_variable_set(:@loaded, false) }

      it "raises error" do
        expect { PhraseKit.stats }.to raise_error(PhraseKit::Error, /not loaded/)
      end
    end

    context "when loaded" do
      before do
        PhraseKit.load!(
          automaton_path: "test",
          payloads_path: "test",
          manifest_path: "test"
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
    end
  end

  describe ".healthcheck" do
    context "when not loaded" do
      before { PhraseKit.instance_variable_set(:@loaded, false) }

      it "raises error" do
        expect { PhraseKit.healthcheck }.to raise_error(PhraseKit::Error)
      end
    end

    context "when loaded" do
      before do
        PhraseKit.load!(
          automaton_path: "test",
          payloads_path: "test",
          manifest_path: "test"
        )
      end

      it "returns true" do
        expect(PhraseKit.healthcheck).to be true
      end
    end
  end
end
