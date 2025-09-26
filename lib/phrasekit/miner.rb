require "shellwords"

module PhraseKit
  class Miner
    class Error < StandardError; end

    class << self
      def mine(input_path:, output_path:, min_n: 2, max_n: 5, min_count: 10, config_path: nil)
        binary_path = find_binary

        # Create temporary config if not provided
        if config_path.nil?
          require "tempfile"
          require "json"

          config_file = Tempfile.new(["mine_config", ".json"])
          config_file.write(JSON.generate({
            min_n: min_n,
            max_n: max_n,
            min_count: min_count
          }))
          config_file.flush
          config_path = config_file.path
        end

        # Run mining
        cmd = [binary_path, input_path.to_s, config_path.to_s, output_path.to_s]
        output = `#{cmd.shelljoin} 2>&1`

        unless $?.success?
          config_file.close! if config_file
          raise Error, "Mining failed: #{output}"
        end

        config_file.close! if config_file

        # Parse stats from output
        parse_stats(output)
      end

      private

      def find_binary
        # Search paths relative to this file
        # __dir__ is lib/phrasekit, so go up 2 levels to get to gem root
        base_dir = File.expand_path("../..", __dir__)

        candidates = [
          File.join(base_dir, "ext/phrasekit/target/release/phrasekit_mine"),
          File.join(base_dir, "ext/phrasekit/target/debug/phrasekit_mine"),
          # For installed gems
          File.join(base_dir, "bin/phrasekit_mine")
        ]

        candidates.each do |binary|
          return binary if File.exist?(binary) && File.executable?(binary)
        end

        raise Error, "phrasekit_mine binary not found. Run: cargo build --release --bin phrasekit_mine --manifest-path ext/phrasekit/Cargo.toml"
      end

      def parse_stats(output)
        stats = {}

        output.scan(/Total documents:\s+(\d+)/) { stats[:total_docs] = $1.to_i }
        output.scan(/Total tokens:\s+(\d+)/) { stats[:total_tokens] = $1.to_i }
        output.scan(/Unique n-grams:\s+(\d+)/) { stats[:unique_ngrams] = $1.to_i }
        output.scan(/After min_count=\d+:\s+(\d+)/) { stats[:ngrams_after_filter] = $1.to_i }

        stats
      end
    end
  end
end