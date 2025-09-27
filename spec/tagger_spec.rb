require "spec_helper"
require "phrasekit"
require "tempfile"
require "json"

RSpec.describe PhraseKit::Tagger do
  describe ".tag" do
    let(:temp_corpus) { Tempfile.new(["corpus", ".jsonl"]) }
    let(:temp_output) { Tempfile.new(["output", ".jsonl"]) }
    let(:artifacts_dir) { Dir.mktmpdir }

    before do
      create_test_artifacts(artifacts_dir)
    end

    after do
      temp_corpus.close!
      temp_output.close!
      FileUtils.rm_rf(artifacts_dir)
    end

    def create_test_artifacts(dir)
      phrases_file = File.join(dir, "phrases.jsonl")
      File.open(phrases_file, "w") do |f|
        f.puts('{"tokens":["test","phrase"],"phrase_id":100,"salience":2.5,"domain_count":10}')
        f.puts('{"tokens":["another","test"],"phrase_id":101,"salience":3.0,"domain_count":15}')
      end

      config_file = File.join(dir, "build_config.json")
      File.write(config_file, JSON.generate({
        version: "test-v1",
        tokenizer: "whitespace",
        separator_id: 4294967294
      }))

      build_binary = File.expand_path("../ext/phrasekit/target/release/phrasekit_build", __dir__)
      result = system(build_binary, phrases_file, config_file, dir, out: File::NULL, err: File::NULL)
      raise "Failed to build test artifacts" unless result
    end

    context "with valid corpus and artifacts" do
      before do
        temp_corpus.puts('{"doc_id":"doc1","tokens":["this","is","a","test","phrase"]}')
        temp_corpus.puts('{"doc_id":"doc2","tokens":["another","test","example"]}')
        temp_corpus.puts('{"doc_id":"doc3","tokens":["no","matches","here"]}')
        temp_corpus.flush
      end

      it "tags phrases successfully" do
        expect {
          PhraseKit::Tagger.tag(
            input_path: temp_corpus.path,
            output_path: temp_output.path,
            artifacts_dir: artifacts_dir
          )
        }.not_to raise_error
      end

      it "returns statistics" do
        stats = PhraseKit::Tagger.tag(
          input_path: temp_corpus.path,
          output_path: temp_output.path,
          artifacts_dir: artifacts_dir
        )

        expect(stats).to be_a(Hash)
        expect(stats[:documents]).to eq(3)
        expect(stats[:total_spans]).to be_a(Integer)
        expect(stats[:docs_with_spans]).to be_a(Integer)
        expect(stats[:avg_spans_per_doc]).to be_a(Float)
      end

      it "produces valid tagged output" do
        PhraseKit::Tagger.tag(
          input_path: temp_corpus.path,
          output_path: temp_output.path,
          artifacts_dir: artifacts_dir
        )

        output = File.readlines(temp_output.path).map { |line| JSON.parse(line) }
        expect(output.size).to eq(3)

        doc = output.first
        expect(doc).to have_key("doc_id")
        expect(doc).to have_key("tokens")
        expect(doc).to have_key("spans")
        expect(doc["spans"]).to be_an(Array)

        if doc["spans"].any?
          span = doc["spans"].first
          expect(span).to have_key("start")
          expect(span).to have_key("end")
          expect(span).to have_key("phrase_id")
          expect(span).to have_key("label")
        end
      end

      it "preserves document IDs and tokens" do
        PhraseKit::Tagger.tag(
          input_path: temp_corpus.path,
          output_path: temp_output.path,
          artifacts_dir: artifacts_dir
        )

        output = File.readlines(temp_output.path).map { |line| JSON.parse(line) }

        doc1 = output.find { |d| d["doc_id"] == "doc1" }
        expect(doc1["tokens"]).to eq(["this", "is", "a", "test", "phrase"])

        doc2 = output.find { |d| d["doc_id"] == "doc2" }
        expect(doc2["tokens"]).to eq(["another", "test", "example"])
      end

      it "finds phrases in matching documents" do
        PhraseKit::Tagger.tag(
          input_path: temp_corpus.path,
          output_path: temp_output.path,
          artifacts_dir: artifacts_dir
        )

        output = File.readlines(temp_output.path).map { |line| JSON.parse(line) }

        doc1 = output.find { |d| d["doc_id"] == "doc1" }
        expect(doc1["spans"]).not_to be_empty

        span = doc1["spans"].first
        matched_tokens = doc1["tokens"][span["start"]...span["end"]]
        expect(matched_tokens).to eq(["test", "phrase"])
      end

      it "handles documents with no matches" do
        PhraseKit::Tagger.tag(
          input_path: temp_corpus.path,
          output_path: temp_output.path,
          artifacts_dir: artifacts_dir
        )

        output = File.readlines(temp_output.path).map { |line| JSON.parse(line) }

        doc3 = output.find { |d| d["doc_id"] == "doc3" }
        expect(doc3["spans"]).to be_empty
      end

      it "respects max_spans parameter" do
        temp_corpus_multi = Tempfile.new(["corpus", ".jsonl"])
        tokens = (["test", "phrase"] * 100).join(",").split(",")
        temp_corpus_multi.puts(JSON.generate({doc_id: "doc_multi", tokens: tokens}))
        temp_corpus_multi.flush

        PhraseKit::Tagger.tag(
          input_path: temp_corpus_multi.path,
          output_path: temp_output.path,
          artifacts_dir: artifacts_dir,
          max_spans: 10
        )

        output = JSON.parse(File.read(temp_output.path))
        expect(output["spans"].size).to be <= 10

        temp_corpus_multi.close!
      end

      it "uses custom label" do
        PhraseKit::Tagger.tag(
          input_path: temp_corpus.path,
          output_path: temp_output.path,
          artifacts_dir: artifacts_dir,
          label: "CUSTOM_ENTITY"
        )

        output = File.readlines(temp_output.path).map { |line| JSON.parse(line) }
        doc_with_spans = output.find { |d| d["spans"].any? }

        if doc_with_spans
          expect(doc_with_spans["spans"].first["label"]).to eq("CUSTOM_ENTITY")
        end
      end
    end

    context "with different matching policies" do
      before do
        temp_corpus.puts('{"doc_id":"doc1","tokens":["test","phrase","test"]}')
        temp_corpus.flush
      end

      it "uses leftmost_longest policy" do
        stats = PhraseKit::Tagger.tag(
          input_path: temp_corpus.path,
          output_path: temp_output.path,
          artifacts_dir: artifacts_dir,
          policy: :leftmost_longest
        )

        expect(stats[:documents]).to eq(1)
      end

      it "uses leftmost_first policy" do
        stats = PhraseKit::Tagger.tag(
          input_path: temp_corpus.path,
          output_path: temp_output.path,
          artifacts_dir: artifacts_dir,
          policy: :leftmost_first
        )

        expect(stats[:documents]).to eq(1)
      end

      it "uses all policy" do
        stats = PhraseKit::Tagger.tag(
          input_path: temp_corpus.path,
          output_path: temp_output.path,
          artifacts_dir: artifacts_dir,
          policy: :all
        )

        expect(stats[:documents]).to eq(1)
      end
    end

    context "with empty corpus" do
      before do
        temp_corpus.flush
      end

      it "handles empty corpus gracefully" do
        stats = PhraseKit::Tagger.tag(
          input_path: temp_corpus.path,
          output_path: temp_output.path,
          artifacts_dir: artifacts_dir
        )

        expect(stats[:documents]).to eq(0)
        expect(stats[:total_spans]).to eq(0)
      end
    end

    context "with corpus containing only non-matching documents" do
      before do
        temp_corpus.puts('{"doc_id":"doc1","tokens":["no","matches"]}')
        temp_corpus.puts('{"doc_id":"doc2","tokens":["nothing","here"]}')
        temp_corpus.flush
      end

      it "tags corpus with zero spans" do
        stats = PhraseKit::Tagger.tag(
          input_path: temp_corpus.path,
          output_path: temp_output.path,
          artifacts_dir: artifacts_dir
        )

        expect(stats[:documents]).to eq(2)
        expect(stats[:total_spans]).to eq(0)
        expect(stats[:docs_with_spans]).to eq(0)
      end
    end

    context "with invalid input" do
      before do
        temp_corpus.puts('{"doc_id":"doc1","tokens":["test"]}')
        temp_corpus.flush
      end

      it "raises error for non-existent corpus file" do
        expect {
          PhraseKit::Tagger.tag(
            input_path: "/nonexistent/corpus.jsonl",
            output_path: temp_output.path,
            artifacts_dir: artifacts_dir
          )
        }.to raise_error(PhraseKit::Tagger::Error, /Tagging failed/)
      end

      it "raises error for non-existent artifacts directory" do
        expect {
          PhraseKit::Tagger.tag(
            input_path: temp_corpus.path,
            output_path: temp_output.path,
            artifacts_dir: "/nonexistent/artifacts"
          )
        }.to raise_error(PhraseKit::Tagger::Error, /Tagging failed/)
      end

      it "raises error when neither artifacts_dir nor individual paths provided" do
        expect {
          PhraseKit::Tagger.tag(
            input_path: temp_corpus.path,
            output_path: temp_output.path
          )
        }.to raise_error(PhraseKit::Tagger::Error, /Must provide either artifacts_dir/)
      end
    end

    context "with explicit artifact paths" do
      before do
        temp_corpus.puts('{"doc_id":"doc1","tokens":["test","phrase"]}')
        temp_corpus.flush
      end

      it "accepts individual artifact paths" do
        expect {
          PhraseKit::Tagger.tag(
            input_path: temp_corpus.path,
            output_path: temp_output.path,
            automaton_path: File.join(artifacts_dir, "phrases.daac"),
            payloads_path: File.join(artifacts_dir, "payloads.bin"),
            manifest_path: File.join(artifacts_dir, "manifest.json"),
            vocab_path: File.join(artifacts_dir, "vocab.json")
          )
        }.not_to raise_error
      end
    end

    context "span correctness" do
      before do
        temp_corpus.puts('{"doc_id":"doc1","tokens":["start","test","phrase","end"]}')
        temp_corpus.flush
      end

      it "produces correct span boundaries" do
        PhraseKit::Tagger.tag(
          input_path: temp_corpus.path,
          output_path: temp_output.path,
          artifacts_dir: artifacts_dir
        )

        output = JSON.parse(File.read(temp_output.path))

        if output["spans"].any?
          span = output["spans"].first
          matched_tokens = output["tokens"][span["start"]...span["end"]]

          expect(span["start"]).to be >= 0
          expect(span["end"]).to be <= output["tokens"].size
          expect(span["end"]).to be > span["start"]
          expect(matched_tokens.size).to be > 0
        end
      end
    end
  end

  describe "binary resolution" do
    it "finds the phrasekit_tag binary" do
      temp_corpus = Tempfile.new(["corpus", ".jsonl"])
      temp_output = Tempfile.new(["output", ".jsonl"])
      artifacts_dir = Dir.mktmpdir

      temp_corpus.puts('{"doc_id":"doc1","tokens":["test"]}')
      temp_corpus.flush

      phrases_file = File.join(artifacts_dir, "phrases.jsonl")
      File.write(phrases_file, '{"tokens":["test"],"phrase_id":1,"salience":1.0,"domain_count":1}')

      config_file = File.join(artifacts_dir, "build_config.json")
      File.write(config_file, JSON.generate({
        version: "test-v1",
        tokenizer: "whitespace",
        separator_id: 4294967294
      }))

      build_binary = File.expand_path("../ext/phrasekit/target/release/phrasekit_build", __dir__)
      system(build_binary, phrases_file, config_file, artifacts_dir, out: File::NULL, err: File::NULL)

      expect {
        PhraseKit::Tagger.tag(
          input_path: temp_corpus.path,
          output_path: temp_output.path,
          artifacts_dir: artifacts_dir
        )
      }.not_to raise_error

      temp_corpus.close!
      temp_output.close!
      FileUtils.rm_rf(artifacts_dir)
    end
  end
end