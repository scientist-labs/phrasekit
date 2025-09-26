require "spec_helper"
require "phrasekit"
require "tempfile"
require "json"

RSpec.describe PhraseKit::Miner do
  describe ".mine" do
    let(:temp_corpus) { Tempfile.new(["corpus", ".jsonl"]) }
    let(:temp_output) { Tempfile.new(["output", ".jsonl"]) }
    let(:temp_config) { Tempfile.new(["config", ".json"]) }

    after do
      temp_corpus.close!
      temp_output.close!
      temp_config.close! if temp_config
    end

    context "with valid corpus" do
      before do
        # Write test corpus
        temp_corpus.puts('{"tokens":["rat","cdk10","oligo"],"doc_id":"1"}')
        temp_corpus.puts('{"tokens":["rat","cdk10","protein"],"doc_id":"2"}')
        temp_corpus.puts('{"tokens":["lysis","buffer"],"doc_id":"3"}')
        temp_corpus.puts('{"tokens":["rat","cdk10"],"doc_id":"4"}')
        temp_corpus.flush
      end

      it "mines n-grams successfully" do
        expect {
          PhraseKit::Miner.mine(
            input_path: temp_corpus.path,
            output_path: temp_output.path,
            min_n: 2,
            max_n: 3,
            min_count: 2
          )
        }.not_to raise_error
      end

      it "returns statistics" do
        stats = PhraseKit::Miner.mine(
          input_path: temp_corpus.path,
          output_path: temp_output.path,
          min_n: 2,
          max_n: 2,
          min_count: 1
        )

        expect(stats).to be_a(Hash)
        expect(stats[:total_docs]).to eq(4)
        expect(stats[:unique_ngrams]).to be > 0
        expect(stats[:ngrams_after_filter]).to be > 0
      end

      it "produces valid output" do
        PhraseKit::Miner.mine(
          input_path: temp_corpus.path,
          output_path: temp_output.path,
          min_n: 2,
          max_n: 2,
          min_count: 2
        )

        output = File.readlines(temp_output.path).map { |line| JSON.parse(line) }
        expect(output).not_to be_empty

        # Check output format
        ngram = output.first
        expect(ngram).to have_key("tokens")
        expect(ngram).to have_key("count")
        expect(ngram["tokens"]).to be_an(Array)
        expect(ngram["count"]).to be_a(Integer)
        expect(ngram["count"]).to be >= 2
      end

      it "filters by min_count" do
        # First with min_count=1
        PhraseKit::Miner.mine(
          input_path: temp_corpus.path,
          output_path: temp_output.path,
          min_n: 2,
          max_n: 2,
          min_count: 1
        )
        results_min1 = File.readlines(temp_output.path).size

        # Then with min_count=3
        PhraseKit::Miner.mine(
          input_path: temp_corpus.path,
          output_path: temp_output.path,
          min_n: 2,
          max_n: 2,
          min_count: 3
        )
        results_min3 = File.readlines(temp_output.path).size

        # Higher min_count should produce fewer results
        expect(results_min3).to be < results_min1
      end

      it "extracts correct n-grams" do
        PhraseKit::Miner.mine(
          input_path: temp_corpus.path,
          output_path: temp_output.path,
          min_n: 2,
          max_n: 2,
          min_count: 2
        )

        output = File.readlines(temp_output.path).map { |line| JSON.parse(line) }
        ngrams = output.map { |ng| ng["tokens"] }

        # "rat cdk10" appears 3 times, should be in output
        expect(ngrams).to include(["rat", "cdk10"])
      end

      it "respects n-gram length limits" do
        PhraseKit::Miner.mine(
          input_path: temp_corpus.path,
          output_path: temp_output.path,
          min_n: 2,
          max_n: 2,
          min_count: 1
        )

        output = File.readlines(temp_output.path).map { |line| JSON.parse(line) }

        # All n-grams should be length 2
        output.each do |ng|
          expect(ng["tokens"].length).to eq(2)
        end
      end
    end

    context "with empty corpus" do
      before do
        temp_corpus.flush
      end

      it "handles empty corpus gracefully" do
        stats = PhraseKit::Miner.mine(
          input_path: temp_corpus.path,
          output_path: temp_output.path,
          min_n: 2,
          max_n: 3,
          min_count: 1
        )

        expect(stats[:total_docs]).to eq(0)
        expect(stats[:ngrams_after_filter]).to eq(0)
      end
    end

    context "with invalid input" do
      it "raises error for non-existent input file" do
        expect {
          PhraseKit::Miner.mine(
            input_path: "/nonexistent/corpus.jsonl",
            output_path: temp_output.path,
            min_n: 2,
            max_n: 3,
            min_count: 1
          )
        }.to raise_error(PhraseKit::Miner::Error, /Mining failed/)
      end
    end

    context "with custom config file" do
      before do
        temp_corpus.puts('{"tokens":["test","phrase"],"doc_id":"1"}')
        temp_corpus.flush

        config = { min_n: 2, max_n: 3, min_count: 1 }
        temp_config.write(JSON.generate(config))
        temp_config.flush
      end

      it "accepts external config file" do
        expect {
          PhraseKit::Miner.mine(
            input_path: temp_corpus.path,
            output_path: temp_output.path,
            config_path: temp_config.path
          )
        }.not_to raise_error
      end
    end

    context "case normalization" do
      before do
        temp_corpus.puts('{"tokens":["RAT","CDK10"],"doc_id":"1"}')
        temp_corpus.puts('{"tokens":["rat","cdk10"],"doc_id":"2"}')
        temp_corpus.puts('{"tokens":["Rat","Cdk10"],"doc_id":"3"}')
        temp_corpus.flush
      end

      it "normalizes tokens to lowercase" do
        PhraseKit::Miner.mine(
          input_path: temp_corpus.path,
          output_path: temp_output.path,
          min_n: 2,
          max_n: 2,
          min_count: 2
        )

        output = File.readlines(temp_output.path).map { |line| JSON.parse(line) }
        rat_cdk10 = output.find { |ng| ng["tokens"] == ["rat", "cdk10"] }

        # All three variants should be counted as one n-gram
        expect(rat_cdk10).not_to be_nil
        expect(rat_cdk10["count"]).to eq(3)
      end
    end
  end

  describe "binary resolution" do
    it "finds the phrasekit_mine binary" do
      # This indirectly tests find_binary by running mine
      # If binary wasn't found, it would raise an error
      temp_corpus = Tempfile.new(["corpus", ".jsonl"])
      temp_output = Tempfile.new(["output", ".jsonl"])

      temp_corpus.puts('{"tokens":["test"],"doc_id":"1"}')
      temp_corpus.flush

      expect {
        PhraseKit::Miner.mine(
          input_path: temp_corpus.path,
          output_path: temp_output.path,
          min_n: 2,
          max_n: 2,
          min_count: 1
        )
      }.not_to raise_error

      temp_corpus.close!
      temp_output.close!
    end
  end
end