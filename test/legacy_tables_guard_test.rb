# frozen_string_literal: true

require "minitest/autorun"

# A table marked legacy holds data that nothing new reads. Only the plumbing that
# writes, prints, counts and declares it may name it.
class LegacyTablesGuardTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  KERNEL = File.join(ROOT, "scripts/lib")
  SCHEMA = File.join(KERNEL, "plastic/graph/db/schema.rb")
  PLUMBING = %w[
    plastic/graph/db/schema.rb
    plastic/graph/schema/metadata.rb
    plastic/graph/knowledge/reader/intent_file.rb
    plastic/graph/knowledge/archive/snapshot_index.rb
    plastic/graph/knowledge/legacy/store_import.rb
    plastic/graph/knowledge/legacy_intents_data.rb
    plastic/graph/prints.rb
    plastic/graph/source.rb
    plastic/graph/retrieval/store_reads.rb
    plastic/graph/retrieval_graph.rb
  ].map { |path| File.join(KERNEL, path) }.freeze
  DECLARATION = /create_table\s+:(\w+)[^\n]*legacy:\s*true/

  def self.legacy_names(text) = text.scan(DECLARATION).flatten

  def self.naming(text, names) = names.select { |name| text.match?(/\b#{Regexp.escape(name)}\b/) }

  def names = self.class.legacy_names(File.read(SCHEMA))

  def test_no_kernel_file_outside_the_plumbing_names_a_legacy_table
    files = Dir.glob(File.join(KERNEL, "**/*.rb")) - PLUMBING

    refute_empty names
    refute_empty files
    offenders = files.select { |path| self.class.naming(File.read(path), names).any? }

    assert_empty offenders, "name a legacy table outside the plumbing: #{offenders.join(", ")}"
  end

  def test_the_detector_catches_a_sample_naming_the_table
    sample = %(rows = database.rows("SELECT * FROM legacy_intents_data"))

    assert_equal ["legacy_intents_data"], self.class.naming(sample, ["legacy_intents_data"])
  end

  def test_the_detector_leaves_a_sample_without_it_alone
    sample = %(legacy_import = 1\nlegacy_intents_data_count = 2\nlegacy_path = "plan.md")

    assert_empty self.class.naming(sample, ["legacy_intents_data"])
  end

  def test_the_declaration_pattern_reads_a_legacy_table_and_skips_the_others
    text = "create_table :old_rows, key: %i[a], legacy: true\ncreate_table :rows, key: %i[a] do |t|"

    assert_equal ["old_rows"], self.class.legacy_names(text)
  end
end
