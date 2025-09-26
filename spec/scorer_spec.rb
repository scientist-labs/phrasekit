require "spec_helper"
require "phrasekit"
require "tempfile"
require "json"

RSpec.describe PhraseKit::Scorer do
  describe ".score" do
    let(:temp_domain) { Tempfile.new(["domain", ".jsonl"]) }
    let(:temp_background) { Tempfile.new(["background", ".jsonl"]) }
    let(:temp_output) { Tempfile.new(["output", ".jsonl"]) }
    let(:temp_config) { Tempfile.new(["config", ".json"]) }

    after do
      temp_domain.close!
      temp_background.close!
      temp_output.close!
      temp_config.close! if temp_config
    end

    context "with valid domain and background corpora" do
      before do
        temp_domain.puts('{"tokens":["rat","cdk10","oligo"],"count":10}')
        temp_domain.puts('{"tokens":["lysis","buffer"],"count":8}')
        temp_domain.puts('{"tokens":["protein","assay","buffer"],"count":5}')
        temp_domain.puts('{"tokens":["for","the"],"count":100}')
        temp_domain.flush

        temp_background.puts('{"tokens":["lysis","buffer"],"count":20}')
        temp_background.puts('{"tokens":["for","the"],"count":50000}')
        temp_background.puts('{"tokens":["in","a"],"count":30000}')
        temp_background.flush
      end

      it "scores phrases successfully with ratio method" do
        expect {
          PhraseKit::Scorer.score(
            domain_path: temp_domain.path,
            background_path: temp_background.path,
            output_path: temp_output.path,
            method: :ratio,
            min_salience: 1.0,
            min_domain_count: 2
          )
        }.not_to raise_error
      end

      it "returns statistics" do
        stats = PhraseKit::Scorer.score(
          domain_path: temp_domain.path,
          background_path: temp_background.path,
          output_path: temp_output.path,
          method: :ratio,
          min_salience: 1.0,
          min_domain_count: 2
        )

        expect(stats).to be_a(Hash)
        expect(stats[:domain_phrases]).to eq(4)
        expect(stats[:background_phrases]).to eq(3)
        expect(stats[:after_domain_filter]).to be > 0
        expect(stats[:after_salience_filter]).to be > 0
      end

      it "produces valid output with phrase IDs" do
        PhraseKit::Scorer.score(
          domain_path: temp_domain.path,
          background_path: temp_background.path,
          output_path: temp_output.path,
          method: :ratio,
          min_salience: 1.0,
          min_domain_count: 2
        )

        output = File.readlines(temp_output.path).map { |line| JSON.parse(line) }
        expect(output).not_to be_empty

        phrase = output.first
        expect(phrase).to have_key("tokens")
        expect(phrase).to have_key("salience")
        expect(phrase).to have_key("phrase_id")
        expect(phrase).to have_key("domain_count")
        expect(phrase).to have_key("background_count")
        expect(phrase["tokens"]).to be_an(Array)
        expect(phrase["salience"]).to be_a(Numeric)
        expect(phrase["phrase_id"]).to be_an(Integer)
      end

      it "filters by min_salience" do
        stats = PhraseKit::Scorer.score(
          domain_path: temp_domain.path,
          background_path: temp_background.path,
          output_path: temp_output.path,
          method: :ratio,
          min_salience: 5.0,
          min_domain_count: 2
        )

        output = File.readlines(temp_output.path).map { |line| JSON.parse(line) }

        output.each do |phrase|
          expect(phrase["salience"]).to be >= 5.0
        end
      end

      it "filters by min_domain_count" do
        stats = PhraseKit::Scorer.score(
          domain_path: temp_domain.path,
          background_path: temp_background.path,
          output_path: temp_output.path,
          method: :ratio,
          min_salience: 0.0,
          min_domain_count: 10
        )

        output = File.readlines(temp_output.path).map { |line| JSON.parse(line) }

        output.each do |phrase|
          expect(phrase["domain_count"]).to be >= 10
        end
      end

      it "assigns sequential phrase IDs" do
        PhraseKit::Scorer.score(
          domain_path: temp_domain.path,
          background_path: temp_background.path,
          output_path: temp_output.path,
          method: :ratio,
          min_salience: 1.0,
          min_domain_count: 2,
          starting_phrase_id: 2000
        )

        output = File.readlines(temp_output.path).map { |line| JSON.parse(line) }
        phrase_ids = output.map { |p| p["phrase_id"] }.sort

        expect(phrase_ids.first).to be >= 2000
        expect(phrase_ids).to eq(phrase_ids.sort)
      end

      it "filters generic phrases with high background counts" do
        stats = PhraseKit::Scorer.score(
          domain_path: temp_domain.path,
          background_path: temp_background.path,
          output_path: temp_output.path,
          method: :ratio,
          min_salience: 2.0,
          min_domain_count: 2
        )

        output = File.readlines(temp_output.path).map { |line| JSON.parse(line) }
        phrases = output.map { |p| p["tokens"] }

        expect(phrases).not_to include(["for", "the"])
      end

      it "keeps domain-specific phrases with low background counts" do
        stats = PhraseKit::Scorer.score(
          domain_path: temp_domain.path,
          background_path: temp_background.path,
          output_path: temp_output.path,
          method: :ratio,
          min_salience: 1.0,
          min_domain_count: 2
        )

        output = File.readlines(temp_output.path).map { |line| JSON.parse(line) }
        phrases = output.map { |p| p["tokens"] }

        expect(phrases).to include(["rat", "cdk10", "oligo"])
      end
    end

    context "with different scoring methods" do
      before do
        temp_domain.puts('{"tokens":["domain","term"],"count":20}')
        temp_domain.puts('{"tokens":["common","word"],"count":10}')
        temp_domain.flush

        temp_background.puts('{"tokens":["common","word"],"count":100}')
        temp_background.flush
      end

      it "scores with ratio method" do
        expect {
          PhraseKit::Scorer.score(
            domain_path: temp_domain.path,
            background_path: temp_background.path,
            output_path: temp_output.path,
            method: :ratio,
            min_salience: 0.0,
            min_domain_count: 1
          )
        }.not_to raise_error

        output = File.readlines(temp_output.path).map { |line| JSON.parse(line) }
        expect(output).not_to be_empty
      end

      it "scores with pmi method" do
        expect {
          PhraseKit::Scorer.score(
            domain_path: temp_domain.path,
            background_path: temp_background.path,
            output_path: temp_output.path,
            method: :pmi,
            min_salience: 0.0,
            min_domain_count: 1
          )
        }.not_to raise_error

        output = File.readlines(temp_output.path).map { |line| JSON.parse(line) }
        expect(output).not_to be_empty
      end

      it "scores with tfidf method" do
        expect {
          PhraseKit::Scorer.score(
            domain_path: temp_domain.path,
            background_path: temp_background.path,
            output_path: temp_output.path,
            method: :tfidf,
            min_salience: 0.0,
            min_domain_count: 1
          )
        }.not_to raise_error

        output = File.readlines(temp_output.path).map { |line| JSON.parse(line) }
        expect(output).not_to be_empty
      end
    end

    context "with empty domain corpus" do
      before do
        temp_domain.flush

        temp_background.puts('{"tokens":["background","phrase"],"count":10}')
        temp_background.flush
      end

      it "handles empty domain corpus gracefully" do
        stats = PhraseKit::Scorer.score(
          domain_path: temp_domain.path,
          background_path: temp_background.path,
          output_path: temp_output.path,
          method: :ratio,
          min_salience: 1.0,
          min_domain_count: 1
        )

        expect(stats[:domain_phrases]).to eq(0)
        expect(stats[:after_salience_filter]).to eq(0)
      end
    end

    context "with empty background corpus" do
      before do
        temp_domain.puts('{"tokens":["domain","phrase"],"count":10}')
        temp_domain.flush

        temp_background.flush
      end

      it "handles empty background corpus gracefully" do
        stats = PhraseKit::Scorer.score(
          domain_path: temp_domain.path,
          background_path: temp_background.path,
          output_path: temp_output.path,
          method: :ratio,
          min_salience: 1.0,
          min_domain_count: 1
        )

        expect(stats[:background_phrases]).to eq(0)
        expect(stats[:after_salience_filter]).to be > 0
      end
    end

    context "with invalid input" do
      before do
        temp_domain.puts('{"tokens":["test"],"count":5}')
        temp_domain.flush

        temp_background.puts('{"tokens":["test"],"count":10}')
        temp_background.flush
      end

      it "raises error for non-existent domain file" do
        expect {
          PhraseKit::Scorer.score(
            domain_path: "/nonexistent/domain.jsonl",
            background_path: temp_background.path,
            output_path: temp_output.path,
            method: :ratio,
            min_salience: 1.0,
            min_domain_count: 1
          )
        }.to raise_error(PhraseKit::Scorer::Error, /Scoring failed/)
      end

      it "raises error for non-existent background file" do
        expect {
          PhraseKit::Scorer.score(
            domain_path: temp_domain.path,
            background_path: "/nonexistent/background.jsonl",
            output_path: temp_output.path,
            method: :ratio,
            min_salience: 1.0,
            min_domain_count: 1
          )
        }.to raise_error(PhraseKit::Scorer::Error, /Scoring failed/)
      end
    end

    context "with custom config file" do
      before do
        temp_domain.puts('{"tokens":["test","phrase"],"count":5}')
        temp_domain.flush

        temp_background.puts('{"tokens":["test","phrase"],"count":2}')
        temp_background.flush

        config = {
          method: "ratio",
          min_salience: 1.0,
          min_domain_count: 2,
          assign_phrase_ids: true,
          starting_phrase_id: 5000
        }
        temp_config.write(JSON.generate(config))
        temp_config.flush
      end

      it "accepts external config file" do
        expect {
          PhraseKit::Scorer.score(
            domain_path: temp_domain.path,
            background_path: temp_background.path,
            output_path: temp_output.path,
            config_path: temp_config.path
          )
        }.not_to raise_error
      end
    end

    context "phrase ID assignment" do
      before do
        temp_domain.puts('{"tokens":["phrase","one"],"count":10}')
        temp_domain.puts('{"tokens":["phrase","two"],"count":10}')
        temp_domain.puts('{"tokens":["phrase","three"],"count":10}')
        temp_domain.flush

        temp_background.flush
      end

      it "disables phrase ID assignment when requested" do
        PhraseKit::Scorer.score(
          domain_path: temp_domain.path,
          background_path: temp_background.path,
          output_path: temp_output.path,
          method: :ratio,
          min_salience: 0.0,
          min_domain_count: 1,
          assign_phrase_ids: false
        )

        output = File.readlines(temp_output.path).map { |line| JSON.parse(line) }

        output.each do |phrase|
          expect(phrase).not_to have_key("phrase_id")
        end
      end

      it "uses custom starting phrase ID" do
        PhraseKit::Scorer.score(
          domain_path: temp_domain.path,
          background_path: temp_background.path,
          output_path: temp_output.path,
          method: :ratio,
          min_salience: 0.0,
          min_domain_count: 1,
          assign_phrase_ids: true,
          starting_phrase_id: 9000
        )

        output = File.readlines(temp_output.path).map { |line| JSON.parse(line) }
        phrase_ids = output.map { |p| p["phrase_id"] }

        expect(phrase_ids.min).to be >= 9000
        expect(phrase_ids.max).to be < 9000 + output.size
      end
    end
  end

  describe "binary resolution" do
    it "finds the phrasekit_score binary" do
      temp_domain = Tempfile.new(["domain", ".jsonl"])
      temp_background = Tempfile.new(["background", ".jsonl"])
      temp_output = Tempfile.new(["output", ".jsonl"])

      temp_domain.puts('{"tokens":["test"],"count":5}')
      temp_domain.flush

      temp_background.puts('{"tokens":["test"],"count":10}')
      temp_background.flush

      expect {
        PhraseKit::Scorer.score(
          domain_path: temp_domain.path,
          background_path: temp_background.path,
          output_path: temp_output.path,
          method: :ratio,
          min_salience: 0.0,
          min_domain_count: 1
        )
      }.not_to raise_error

      temp_domain.close!
      temp_background.close!
      temp_output.close!
    end
  end
end