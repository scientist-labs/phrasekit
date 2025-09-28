#!/usr/bin/env ruby

# Helper script to prepare product data for PhraseKit
# Usage: ruby scripts/prepare_corpus.rb

require "json"

puts "PhraseKit Corpus Preparation Helper"
puts "=" * 70
puts

# Example: Convert your product data to JSONL format
# Modify this to match your data structure

def tokenize(text)
  # Simple tokenization: lowercase, split on whitespace, clean
  text.downcase
    .gsub(/\n+/, ' ')  # Replace newlines with spaces
    .split(/\s+/)
    .map { |t| t.gsub(/[^\w-]/, '') }  # Keep alphanumeric and hyphens
    .reject(&:empty?)
end

# Example 1: From CSV
def from_csv(input_path, output_path)
  require 'csv'

  count = 0
  File.open(output_path, "w") do |f|
    CSV.foreach(input_path, headers: true) do |row|
      # Adjust column names to match your CSV
      text = [
        row['title'],
        row['description'],
        row['specifications']
      ].compact.join(' ')

      tokens = tokenize(text)
      next if tokens.empty?

      f.puts JSON.generate({
        doc_id: row['id'] || count.to_s,
        tokens: tokens
      })

      count += 1
      print "\rProcessed #{count} products..." if count % 1000 == 0
    end
  end

  puts "\n✓ Wrote #{count} products to #{output_path}"
end

# Example 2: From database (ActiveRecord)
def from_database(output_path, limit: nil)
  # Uncomment and modify for your model:

  # require './config/environment'  # Rails

  count = 0
  File.open(output_path, "w") do |f|
    query = Product.all
    query = query.limit(limit) if limit

    query.find_each(batch_size: 1000) do |product|
      text = [
        product.title,
        product.description,
        product.specifications
      ].compact.join(' ')

      tokens = tokenize(text)
      next if tokens.empty?

      f.puts JSON.generate({
        doc_id: product.id.to_s,
        tokens: tokens
      })

      count += 1
      print "\rProcessed #{count} products..." if count % 1000 == 0
    end
  end

  puts "\n✓ Wrote #{count} products to #{output_path}"
end

# Example 3: From JSON file
def from_json(input_path, output_path)
  count = 0

  File.open(output_path, "w") do |f|
    File.open(input_path) do |input|
      input.each_line do |line|
        product = JSON.parse(line)

        # Adjust field names to match your JSON structure
        text = [
          product['title'],
          product['description'],
          product['specs']
        ].compact.join(' ')

        tokens = tokenize(text)
        next if tokens.empty?

        f.puts JSON.generate({
          doc_id: product['id'] || count.to_s,
          tokens: tokens
        })

        count += 1
        print "\rProcessed #{count} products..." if count % 1000 == 0
      end
    end
  end

  puts "\n✓ Wrote #{count} products to #{output_path}"
end

# Quick test with sample data
def create_sample(output_path = "sample_corpus.jsonl", count: 1000)
  puts "Creating sample corpus with #{count} products..."

  # Biotech product examples
  templates = [
    "anti %s antibody monoclonal igg %s ug",
    "%s protein recombinant human %s mg",
    "%s assay kit elisa %s tests",
    "western blot %s buffer %s ml",
    "%s reagent grade %s g",
    "%s cell line %s passage",
    "%s enzyme purified %s units",
    "pcr %s primer set %s reactions"
  ]

  proteins = %w[cdk10 brca1 tp53 egfr il6 tnf cd3 cd4 cd8 bcl2]
  sizes = %w[100 250 500 1000 50 25]

  File.open(output_path, "w") do |f|
    count.times do |i|
      template = templates.sample
      protein = proteins.sample
      size = sizes.sample

      text = template % [protein, size]
      tokens = tokenize(text)

      f.puts JSON.generate({
        doc_id: "prod_#{i}",
        tokens: tokens
      })
    end
  end

  puts "✓ Created #{output_path}"
end

# Main
if __FILE__ == $0
  puts "Choose an option:"
  puts "  1. Create sample corpus (for testing)"
  puts "  2. Convert from CSV"
  puts "  3. Convert from database (ActiveRecord)"
  puts "  4. Convert from JSON"
  puts
  print "Option (1-4): "

  option = gets.chomp.to_i

  case option
  when 1
    print "How many sample products? [1000]: "
    count = gets.chomp
    count = count.empty? ? 1000 : count.to_i

    create_sample("sample_corpus.jsonl", count: count)

  when 2
    print "Input CSV path: "
    input_path = gets.chomp

    print "Output JSONL path [corpus.jsonl]: "
    output_path = gets.chomp
    output_path = "corpus.jsonl" if output_path.empty?

    from_csv(input_path, output_path)

  when 3
    print "Output JSONL path [corpus.jsonl]: "
    output_path = gets.chomp
    output_path = "corpus.jsonl" if output_path.empty?

    print "Limit (leave empty for all): "
    limit = gets.chomp
    limit = limit.empty? ? nil : limit.to_i

    from_database(output_path, limit: limit)

  when 4
    print "Input JSON path: "
    input_path = gets.chomp

    print "Output JSONL path [corpus.jsonl]: "
    output_path = gets.chomp
    output_path = "corpus.jsonl" if output_path.empty?

    from_json(input_path, output_path)

  else
    puts "Invalid option"
  end
end