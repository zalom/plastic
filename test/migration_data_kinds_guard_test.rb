# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/plastic/graph/migration/store_migration"

# A migration that drops a table, a column or rows states which kind the data is, in LegacyKeep::KINDS: the owner's data,
# kept in legacy.db with an undo, a mistake, deleted with no copy and no undo, or rebuilt, which loses nothing.
class MigrationDataKindsGuardTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  FOLDER = File.join(ROOT, "lib/plastic/graph/db/migrate/store")
  DROPS = /\b(?:DROP\s+(?:TABLE|COLUMN)|DELETE\s+FROM)\b/i
  Keep = Plastic::Graph::LegacyKeep

  # The text of `source` without its comment lines, SQL or Ruby.
  def self.code(source) = source.lines.grep_v(/\A\s*(?:--|#)/).join

  def self.drops?(source) = code(source).match?(DROPS)

  def version_of(path) = File.basename(path)[0, 14]

  def step_file(version)
    step = Plastic::Graph::StoreMigration::DATA_STEPS[version]
    step && Object.const_source_location(step.name).first
  end

  # The versions whose SQL file or data step drops data.
  def dropping
    Dir.glob(File.join(FOLDER, "*.sql")).select { |path| [path, step_file(version_of(path))].compact.any? { |file| self.class.drops?(File.read(file)) } }.map { |path| version_of(path) }
  end

  def test_every_migration_that_drops_data_states_its_kind
    refute_empty dropping
    assert_empty dropping - Keep::KINDS.keys, "state the kind of the data they drop in LegacyKeep::KINDS"
  end

  def test_every_stated_kind_is_one_of_the_three_and_belongs_to_a_store_migration
    versions = Dir.glob(File.join(FOLDER, "*.sql")).map { |path| version_of(path) }

    assert_empty Keep::KINDS.values.uniq - %i[owner mistake rebuilt]
    assert_empty Keep::KINDS.keys - versions
  end

  def test_the_owners_data_is_what_a_migration_keeps_in_legacy_db_and_a_mistake_is_never_kept
    owners = Keep::KINDS.select { |_version, kind| kind == :owner }.keys
    mistakes = Keep::KINDS.select { |_version, kind| kind == :mistake }.keys

    assert_equal Keep::KEEPS.sort, owners.sort
    assert_empty mistakes & Keep::KEEPS
  end

  def test_the_detector_catches_a_drop_and_a_delete
    samples = ["DROP TABLE IF EXISTS main.document_revisions;", %(ALTER TABLE work."nodes" DROP COLUMN "input";), %(DELETE FROM main.sqlar WHERE name = ?)]

    assert_equal [true] * 3, samples.map { |sql| self.class.drops?(sql) }
  end

  def test_the_detector_leaves_a_comment_alone
    notes = ["-- The tables go: DROP TABLE is only named here.\nSELECT 1;", "# DELETE FROM is named in this note\nCREATE TABLE a(b);"]

    assert_equal [false] * 2, notes.map { |sql| self.class.drops?(sql) }
  end
end
