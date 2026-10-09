# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../scripts/lib/plastic/routine"
require_relative "../../scripts/lib/plastic/cli/table"

Dir[File.join(__dir__, "../../scripts/lib/plastic/commands/*.rb")].each { |file| require file }

class PrintsDeclarationTest < Minitest::Test
  NO_FILE = {
    "SessionNote" => "its rows are the session ledger, which no file holds",
    "Backup" => "a backup copies the databases, which no printed file holds",
    "BackupPurge" => "it removes backup records, which no printed file holds",
    "BackupRestore" => "it restores databases and hands the files to sync down",
    "SyncUp" => "sync prints through its own plan",
    "SyncDown" => "sync prints through its own plan"
  }.freeze

  def routines
    Plastic::CLI::TABLE.values.map(&:first).uniq.grep(/\ACommands::/).map { |name| Object.const_get("Plastic::#{name}") }
      .select { |klass| klass < Plastic::Routine }
  end

  def writers = routines.select { |klass| klass.writes.any? }

  def short(klass) = klass.name.split("::").last

  def test_there_are_routines_that_write
    refute_empty writers
  end

  def test_every_routine_that_writes_declares_prints_or_is_named_without_a_file
    missing = writers.reject { |klass| klass.prints.any? || NO_FILE.key?(short(klass)) }.map { |klass| short(klass) }

    assert_empty missing
  end

  def test_the_named_exceptions_are_routines_that_write
    assert_empty NO_FILE.keys - writers.map { |klass| short(klass) }
  end

  def test_prints_takes_only_intent_roadmap_and_index
    error = assert_raises(Plastic::Invalid) { Class.new(Plastic::Routine) { prints :everything } }

    assert_includes error.message, "everything"
  end

  def test_the_detector_sees_a_writer_without_prints
    sample = Class.new(Plastic::Routine) { writes :work }

    assert_empty sample.prints
    assert_predicate sample.writes, :any?
  end
end
