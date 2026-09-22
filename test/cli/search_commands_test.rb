# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "tmpdir"
require_relative "../lib/cli_fixture"
require_relative "../../scripts/lib/cli"
require_relative "../../scripts/lib/search_index"

class CliSearchCommandsTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("plastic-cli-search")
    @fixture = CliFixture.new(@dir).global_store(active: [["1", "Alpha"]]).project("acme", active: [["2", "Beta"]])
    seed("store/1--alpha/spec.md", "# Spec\n\nThe heron nests by the river in spring.\n")
    seed("projects/acme/store/2--beta/spec.md", "# Spec\n\nA heron was seen at the acme pond.\n")
    seed("store/.sessions/20260921/handoff.md", "Hand-off: the heron count is open.\n")
  end

  def teardown
    File.chmod(0o755, @fixture.plastic_home)
    FileUtils.remove_entry(@dir)
  end

  def seed(relative, body)
    path = File.join(@fixture.plastic_home, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end

  def plastic(*argv)
    [@fixture.out, @fixture.err].each do |io|
      io.truncate(0)
      io.rewind
    end
    Plastic::CLI.call(argv, directory: "/nowhere", **@fixture.streams)
  end

  def database
    File.join(@fixture.plastic_home, "knowledge_graph.db")
  end

  def test_index_builds_the_database_and_prints_the_file_count
    assert_equal 0, plastic("index")

    assert_path_exists database
    assert_includes @fixture.printed, "6 files"
  end

  def test_index_names_search_as_the_next_step
    plastic("index")

    assert_includes @fixture.printed, "next: plastic search TERMS"
  end

  def test_index_stores_paths_relative_to_the_plastic_home
    plastic("index")

    paths = Plastic::Sqlite.call(database, "SELECT path FROM doc ORDER BY path").map { |row| row["path"] }

    assert_includes paths, "store/1--alpha/spec.md"
    assert_includes paths, "store/.sessions/20260921/handoff.md"
  end

  def test_a_failed_build_keeps_the_old_database
    plastic("index")
    before = File.binread(database)
    File.chmod(0o555, @fixture.plastic_home)

    assert_equal 1, plastic("index")
    assert_equal before, File.binread(database)
    refute_path_exists "#{database}.tmp"
  end

  def test_a_failed_build_prints_the_message_of_sqlite3
    File.chmod(0o555, @fixture.plastic_home)
    plastic("index")

    assert_includes @fixture.warned, "unable to open"
  end

  def test_search_prints_the_path_and_an_excerpt
    plastic("index")
    plastic("search", "river")

    assert_includes @fixture.printed, "store/1--alpha/spec.md"
    assert_includes @fixture.printed, "[river]"
  end

  def test_search_names_the_index_date_in_its_because_line
    plastic("index")
    plastic("search", "river")

    assert_includes @fixture.printed, "because: the search is complete"
  end

  def test_search_honors_limit
    plastic("index")
    plastic("search", "heron", "--limit", "1", "--json")

    assert_equal 1, JSON.parse(@fixture.printed)["result"].size
  end

  def test_search_honors_project
    plastic("index")
    plastic("search", "heron", "--project", "acme", "--json")

    assert_equal ["projects/acme/store/2--beta/spec.md"], JSON.parse(@fixture.printed)["result"].keys
  end

  def test_search_with_an_unknown_project_exits_two
    plastic("index")

    assert_equal 2, plastic("search", "heron", "--project", "nope")
  end

  def test_search_takes_punctuation_as_plain_words
    plastic("index")

    assert_equal 0, plastic("search", "hand-off")
    assert_includes @fixture.printed, "handoff.md"
  end

  def test_ask_drops_the_stop_words_and_ranks_the_file_with_both_terms_first
    plastic("index")
    plastic("search", "--ask", "Where is the heron by the river?")

    assert_match(/\Astore\/1--alpha\/spec\.md .*\n(.*\n)*projects\/acme/, @fixture.printed)
  end

  def test_search_with_no_match_says_so
    plastic("index")
    plastic("search", "zebra")

    assert_includes @fixture.printed, "no match"
  end

  def test_search_without_terms_exits_two
    assert_equal 2, plastic("search")
  end

  def test_search_without_a_database_exits_one_and_names_plastic_index
    assert_equal 1, plastic("search", "heron")
    assert_includes @fixture.warned, "plastic index"
  end

  def test_query_prints_the_rows
    plastic("index")
    plastic("query", "SELECT count(*) AS n FROM doc")

    assert_includes @fixture.printed, "n=6"
  end

  def test_query_refuses_a_write_and_leaves_the_rows
    plastic("index")

    assert_equal 1, plastic("query", "DELETE FROM doc")
    assert_includes @fixture.warned, "readonly"
    assert_equal 6, Plastic::Sqlite.call(database, "SELECT count(*) AS n FROM doc").first["n"]
  end

  def test_query_without_sql_exits_two
    assert_equal 2, plastic("query")
  end

  def test_query_without_a_database_exits_one
    assert_equal 1, plastic("query", "SELECT 1")
  end

  def test_search_on_a_broken_index_exits_one
    plastic("index")
    File.write(database, "not a database")

    assert_equal 1, plastic("search", "heron")
  end
end
