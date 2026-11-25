# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/console/databases"

# The four databases of the console, each its own read-only connection.
class ConsoleDatabasesTest < Plastic::TestCase
  fixtures :alpha

  def scope = Plastic::Scope.new(env: { "PLASTIC_HOME" => @plastic_home }, home: @home, slug: nil, directory: @home)

  def test_the_names_are_the_stems_of_the_four_files
    assert_equal %i[work knowledge retrieval plastic], Plastic::Console::Databases::NAMES
  end

  def test_each_name_reads_its_own_file
    databases = Plastic::Console::Databases.open(scope)
    paths = Plastic::Console::Databases::NAMES.map { |name| File.basename(databases.public_send(name).filename) }

    assert_equal %w[work_graph.db knowledge_graph.db retrieval_graph.db plastic.db], paths
  ensure
    databases&.close
  end

  def test_each_name_is_open_read_only
    databases = Plastic::Console::Databases.open(scope)

    assert_equal [true] * 4, Plastic::Console::Databases::NAMES.map { |name| databases.public_send(name).readonly? }
  ensure
    databases&.close
  end

  def test_evaluate_runs_the_code_with_the_names_as_methods
    databases = Plastic::Console::Databases.open(scope)

    assert_equal 2, databases.evaluate("work; knowledge; 1 + 1")
  ensure
    databases&.close
  end

  def test_a_store_folder_that_does_not_exist_is_refused
    missing = Struct.new(:slug, :root).new("gone", File.join(@home, "gone"))

    assert_raises(Plastic::Graph::MissingStore) { Plastic::Console::Databases.open(missing) }
  end
end
