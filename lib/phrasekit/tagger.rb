require "shellwords"

module PhraseKit
  class Tagger
    class Error < StandardError; end

    class << self
      def tag(
        input_path:,
        output_path:,
        artifacts_dir: nil,
        automaton_path: nil,
        payloads_path: nil,
        manifest_path: nil,
        vocab_path: nil,
        policy: :leftmost_longest,
        max_spans: 100,
        label: "PHRASE",
        config_path: nil
      )
        binary_path = find_binary

        if config_path.nil?
          require "tempfile"
          require "json"

          if artifacts_dir
            automaton_path ||= File.join(artifacts_dir, "phrases.daac")
            payloads_path ||= File.join(artifacts_dir, "payloads.bin")
            manifest_path ||= File.join(artifacts_dir, "manifest.json")
            vocab_path ||= File.join(artifacts_dir, "vocab.json")
          end

          unless automaton_path && payloads_path && manifest_path && vocab_path
            raise Error, "Must provide either artifacts_dir or all artifact paths"
          end

          config_file = Tempfile.new(["tag_config", ".json"])
          config_file.write(JSON.generate({
            automaton_path: automaton_path.to_s,
            payloads_path: payloads_path.to_s,
            manifest_path: manifest_path.to_s,
            vocab_path: vocab_path.to_s,
            policy: policy.to_s,
            max_spans: max_spans,
            label: label.to_s
          }))
          config_file.flush
          config_path = config_file.path
        end

        cmd = [
          binary_path,
          input_path.to_s,
          config_path.to_s,
          output_path.to_s
        ]
        output = `#{cmd.shelljoin} 2>&1`

        unless $?.success?
          config_file.close! if config_file
          raise Error, "Tagging failed: #{output}"
        end

        config_file.close! if config_file

        parse_stats(output)
      end

      private

      def find_binary
        base_dir = File.expand_path("../..", __dir__)

        candidates = [
          File.join(base_dir, "ext/phrasekit/target/release/phrasekit_tag"),
          File.join(base_dir, "ext/phrasekit/target/debug/phrasekit_tag"),
          File.join(base_dir, "bin/phrasekit_tag")
        ]

        candidates.each do |binary|
          return binary if File.exist?(binary) && File.executable?(binary)
        end

        raise Error, "phrasekit_tag binary not found. Run: cargo build --release --bin phrasekit_tag --manifest-path ext/phrasekit/Cargo.toml"
      end

      def parse_stats(output)
        stats = {}

        output.scan(/Documents:\s+(\d+)/) { stats[:documents] = $1.to_i }
        output.scan(/Total spans:\s+(\d+)/) { stats[:total_spans] = $1.to_i }
        output.scan(/Documents with spans:\s+(\d+)/) { stats[:docs_with_spans] = $1.to_i }
        output.scan(/Avg spans per document:\s+([\d.]+)/) { stats[:avg_spans_per_doc] = $1.to_f }

        stats
      end
    end
  end
end