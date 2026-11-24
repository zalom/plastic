# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/plastic/routine"
require_relative "../../lib/plastic/cli/table"
Dir[File.join(__dir__, "../../lib/plastic/commands/**/*.rb")].each { |file| require file }

# The retrieval graph is written by classes the commands reach, so a command can write it
# without saying so. This guard finds every class that writes the retrieval database and
# fails when a class is not named here or a command it names does not declare the write.
class RetrievalWritesGuardTest < Minitest::Test
  LIB = File.expand_path("../../lib", __dir__)
  WRITING = /\.reindex\b|Evidence::Writer|retrieval\.repair|\.rebuild_index/
  OWN = %r{\Aplastic/graph/retrieval/}

  COMMANDS_OF = {
    "plastic/doctor/search_index.rb" => %w[Doctor],
    "plastic/graph/backup/store_backups.rb" => %w[Store::Backup::Restore],
    "plastic/workflows/code/backup/restore.rb" => %w[Store::Backup::Restore],
    "plastic/graph/knowledge/archive/operation.rb" => %w[Intent::Archive Intent::Unarchive],
    "plastic/graph/knowledge/archive/snapshot_index.rb" => %w[Intent::Archive Intent::Unarchive],
    "plastic/graph/knowledge/intent/document_writer.rb" => %w[Intent::Note Intent::Spec Intent::Outcome],
    "plastic/graph/knowledge/intent/reporter.rb" => %w[Intent::Report],
    "plastic/graph/knowledge/intent/reviser.rb" => %w[Intent::Revise],
    "plastic/graph/knowledge/intent/writer.rb" => %w[Intent::New],
    "plastic/graph/knowledge/repair/run.rb" => %w[Intent::Repair],
    "plastic/graph/knowledge/sync.rb" => %w[Store::Sync::Up Store::Sync::Down],
    "plastic/graph/migration/store_compaction.rb" => %w[Update Install],
    "plastic/graph/work/completion/writer.rb" => %w[Intent::End Intent::Abandon]
  }.freeze

  def self.writing_files
    Dir.glob(File.join(LIB, "plastic/**/*.rb")).map { |path| path.delete_prefix("#{LIB}/") }
      .reject { |path| path.match?(OWN) }.select { |path| File.read(File.join(LIB, path)).match?(WRITING) }.sort
  end

  def command(name) = Plastic::Commands.const_get(name)

  def table_commands
    Plastic::CLI::TABLE.values.map(&:first).uniq.grep(/\ACommands::/).map { |name| Object.const_get("Plastic::#{name}") }.select { |klass| klass < Plastic::Routine }
  end

  def test_every_class_that_writes_the_retrieval_database_is_named_with_its_commands
    assert_empty self.class.writing_files - COMMANDS_OF.keys, "a class writes retrieval_graph.db and no command is named for it"
    assert_empty COMMANDS_OF.keys - self.class.writing_files, "a named class no longer writes retrieval_graph.db"
  end

  def test_every_command_of_a_writing_class_declares_writes_retrieval
    COMMANDS_OF.each do |path, names|
      names.each { |name| assert_includes command(name).writes, :retrieval, "#{name} reaches #{path} and declares writes :retrieval" }
    end
  end

  def test_no_command_declares_writes_retrieval_without_a_writing_class
    declared = table_commands.select { |klass| klass.writes.include?(:retrieval) }.map { |klass| klass.name.delete_prefix("Plastic::Commands::") }

    assert_empty declared - COMMANDS_OF.values.flatten
  end

  def architecture_row = File.readlines(File.expand_path("../../docs/contributing/ARCHITECTURE.md", __dir__)).find { |line| line.start_with?("| Retrieval graph") }

  def words_of(klass) = klass.name.delete_prefix("Plastic::Commands::").split("::").map(&:downcase).join(" ")

  def test_the_architecture_row_names_every_writer_and_reader_from_the_declarations
    named = table_commands.select { |klass| [*klass.writes, *klass.reads].include?(:retrieval) }.map { |klass| words_of(klass) }
    missing = ["search", *named].uniq.reject { |words| architecture_row.include?("`plastic #{words}`") }

    assert_empty missing
  end
end
