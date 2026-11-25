# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/plastic/graph/migration/store_migration"
require_relative "../lib/plastic/graph/migration/home_migration"

# A migration that drops a table, a column or rows states which kind the data is: the owner's data, kept with an undo,
# a mistake, deleted with no copy and no undo, or rebuilt, which loses nothing. A store migration states it in
# LegacyKeep::KINDS and a home migration in HomeMigration::KINDS, since a home and a store migration may share a version.
class MigrationDataKindsGuardTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  STORE = File.join(ROOT, "lib/plastic/graph/db/migrate/store")
  HOME = File.join(ROOT, "lib/plastic/graph/db/migrate/home")
  DOC = File.join(ROOT, "docs/contributing/MIGRATIONS.md")
  DROPS = /\b(?:DROP\s+(?:TABLE|COLUMN)|DELETE\s+FROM)\b/i
  THREE = %i[owner mistake rebuilt].freeze
  Keep = Plastic::Graph::LegacyKeep

  # The text of `source` without its comment lines, SQL or Ruby.
  def self.code(source) = source.lines.grep_v(/\A\s*(?:--|#)/).join

  def self.drops?(source) = code(source).match?(DROPS)

  def home_kinds = Plastic::Graph::HomeMigration::KINDS

  def version_of(path) = File.basename(path)[0, 14]

  def versions(folder) = Dir.glob(File.join(folder, "*.sql")).map { |path| version_of(path) }

  def step_file(version)
    step = Plastic::Graph::StoreMigration::DATA_STEPS[version]
    step && Object.const_source_location(step.name).first
  end

  # The versions of `folder` whose SQL file, or with `steps` whose data step, drops data.
  def dropping(folder, steps: false)
    Dir.glob(File.join(folder, "*.sql")).select { |path| [path, (step_file(version_of(path)) if steps)].compact.any? { |file| self.class.drops?(File.read(file)) } }
      .map { |path| version_of(path) }
  end

  def test_every_store_migration_that_drops_data_states_its_kind
    refute_empty dropping(STORE, steps: true)
    assert_empty dropping(STORE, steps: true) - Keep::KINDS.keys, "state the kind of the data they drop in LegacyKeep::KINDS"
  end

  def test_every_home_migration_that_drops_data_states_its_kind
    refute_empty dropping(HOME)
    assert_empty dropping(HOME) - home_kinds.keys, "state the kind of the data they drop in HomeMigration::KINDS"
  end

  def test_every_stated_kind_is_one_of_the_three_and_belongs_to_a_store_migration
    assert_empty Keep::KINDS.values.uniq - THREE
    assert_empty Keep::KINDS.keys - versions(STORE)
  end

  def test_every_stated_home_kind_is_one_of_the_three_and_belongs_to_a_home_migration
    assert_empty home_kinds.values.uniq - THREE
    assert_empty home_kinds.keys - versions(HOME)
  end

  def test_the_owners_data_is_what_a_migration_keeps_in_legacy_db_and_a_mistake_is_never_kept
    owners = Keep::KINDS.select { |_version, kind| kind == :owner }.keys
    mistakes = Keep::KINDS.select { |_version, kind| kind == :mistake }.keys

    assert_equal Keep::KEEPS.sort, owners.sort
    assert_empty mistakes & Keep::KEEPS
  end

  def test_the_migrations_doc_defines_each_kind_and_names_where_a_home_migration_states_it
    text = File.read(DOC)

    assert_equal [true] * 4, ["The owner's data is", "A mistake is", "Rebuilt data is", "`HomeMigration::KINDS`"].map { |words| text.include?(words) }
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
