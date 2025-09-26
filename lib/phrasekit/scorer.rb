require "shellwords"

module PhraseKit
  class Scorer
    class Error < StandardError; end

    class << self
      def score(
        domain_path:,
        background_path:,
        output_path:,
        method: :ratio,
        min_salience: 2.0,
        min_domain_count: 10,
        assign_phrase_ids: true,
        starting_phrase_id: 1000,
        config_path: nil
      )
        binary_path = find_binary

        # Create temporary config if not provided
        if config_path.nil?
          require "tempfile"
          require "json"

          config_file = Tempfile.new(["score_config", ".json"])
          config_file.write(JSON.generate({
            method: method.to_s,
            min_salience: min_salience,
            min_domain_count: min_domain_count,
            assign_phrase_ids: assign_phrase_ids,
            starting_phrase_id: starting_phrase_id
          }))
          config_file.flush
          config_path = config_file.path
        end

        # Run scoring
        cmd = [
          binary_path,
          domain_path.to_s,
          background_path.to_s,
          config_path.to_s,
          output_path.to_s
        ]
        output = `#{cmd.shelljoin} 2>&1`

        unless $?.success?
          config_file.close! if config_file
          raise Error, "Scoring failed: #{output}"
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
          File.join(base_dir, "ext/phrasekit/target/release/phrasekit_score"),
          File.join(base_dir, "ext/phrasekit/target/debug/phrasekit_score"),
          # For installed gems
          File.join(base_dir, "bin/phrasekit_score")
        ]

        candidates.each do |binary|
          return binary if File.exist?(binary) && File.executable?(binary)
        end

        raise Error, "phrasekit_score binary not found. Run: cargo build --release --bin phrasekit_score --manifest-path ext/phrasekit/Cargo.toml"
      end

      def parse_stats(output)
        stats = {}

        output.scan(/Domain phrases:\s+(\d+)/) { stats[:domain_phrases] = $1.to_i }
        output.scan(/Background phrases:\s+(\d+)/) { stats[:background_phrases] = $1.to_i }
        output.scan(/After domain filter:\s+(\d+)/) { stats[:after_domain_filter] = $1.to_i }
        output.scan(/After salience filter:\s+(\d+)/) { stats[:after_salience_filter] = $1.to_i }

        stats
      end
    end
  end
end