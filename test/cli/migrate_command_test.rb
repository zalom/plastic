# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"
require_relative "../lib/cli_fixture"
require_relative "../../scripts/lib/cli"
require_relative "../../scripts/doctor"

class CliMigrateCommandTest < Minitest::Test
  SPEC = "1--alpha/spec.md"

  def setup
    @dir = Dir.mktmpdir("plastic-cli-migrate")
    @fixture = CliFixture.new(@dir).global_store(active: [["1", "Alpha"]]).project("acme", active: [["2", "Beta"]])
    seed("store/#{SPEC}", "# Spec\n\nThe heron nests by the river.\n")
    seed("store/1--alpha/resources/shot.png", "\x89PNG binary".b)
    seed("roadmaps/big.md", "# Big\n")
    seed("projects/acme/roadmaps/small.md", "# Small\n")
    seed("projects/.gitkeep", "")
    seed("config.yml", "channel: stable\nproject_roots:\n  - \"~/.plastic/projects\"\n")
    File.write(qmd_index, "collections:\n  plastic-global:\n    path: #{home}/store\n  plastic-acme:\n    path: #{home}/projects/acme/store\n", mode: "w")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def home
    @fixture.plastic_home
  end

  def copy
    "#{home}-before-stores-move"
  end

  def qmd_index
    path = File.join(@fixture.home, ".config", "qmd", "index.yml")
    FileUtils.mkdir_p(File.dirname(path))
    path
  end

  def seed(relative, body)
    path = File.join(home, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, body)
  end

  def plastic(*argv)
    [@fixture.out, @fixture.err].each do |io|
      io.truncate(0)
      io.rewind
    end
    Plastic::CLI.call(argv, directory: @dir, **@fixture.streams)
  end

  def paths(database, statement)
    Plastic::Sqlite.call(File.join(home, database), statement).map(&:values).flatten.sort
  end

  def test_a_dry_run_prints_every_move_and_changes_nothing
    plastic("migrate", "stores", "--dry-run")

    assert_match(%r{^move\s+projects/acme -> stores/acme$}, @fixture.printed)
    refute_path_exists File.join(home, "stores")
    refute_path_exists copy
  end

  def test_the_global_store_its_index_and_its_roadmaps_move_under_global
    assert_equal 0, plastic("migrate", "stores")

    %W[store/#{SPEC} INDEX.md roadmaps/big.md].each { |file| assert_path_exists File.join(home, "stores", "global", file) }
  end

  def test_a_project_moves_with_its_roadmaps
    plastic("migrate", "stores")

    assert_path_exists File.join(home, "stores", "acme", "store")
    assert_path_exists File.join(home, "stores", "acme", "roadmaps", "small.md")
    refute_path_exists File.join(home, "projects")
  end

  def test_the_copy_keeps_the_old_layout
    plastic("migrate", "stores")

    assert_path_exists File.join(copy, "store", SPEC)
    assert_path_exists File.join(copy, "projects", "acme", "INDEX.md")
  end

  def test_the_run_prints_the_command_that_removes_the_copy
    plastic("migrate", "stores")

    assert_includes @fixture.printed, "rm -rf #{copy}"
    assert_includes @fixture.printed, "next: plastic doctor"
  end

  def test_the_project_roots_in_the_config_are_rewritten
    plastic("migrate", "stores")

    assert_includes File.read(File.join(home, "config.yml")), "\"~/.plastic/stores\""
  end

  def test_the_qmd_collection_paths_are_rewritten_and_the_old_file_is_kept
    before = File.read(qmd_index)
    plastic("migrate", "stores")

    assert_includes File.read(qmd_index), "path: #{home}/stores/global/store\n"
    assert_includes File.read(qmd_index), "path: #{home}/stores/acme/store\n"
    assert_equal before, File.read("#{qmd_index}.before-stores-move")
  end

  def test_the_database_rows_name_the_new_paths
    plastic("sync")
    plastic("migrate", "stores")

    assert_includes paths("knowledge_graph.db", "SELECT path FROM doc"), "stores/global/store/#{SPEC}"
    assert_includes paths("knowledge_graph.db", "SELECT path FROM doc"), "stores/acme/store/2--beta/plan.md"
    assert_equal ["stores/.gitkeep", "stores/global/store/1--alpha/resources/shot.png"], paths("references.db", "SELECT name FROM sqlar")
  end

  def test_a_sync_after_the_move_reads_only_the_global_index_and_roadmap
    plastic("sync")
    plastic("migrate", "stores")

    assert_equal 0, plastic("sync")
    assert_match(%r{\Aread  stores/global/INDEX.md\n      stores/global/roadmaps/big.md\n\n}, @fixture.printed)
  end

  def test_status_lists_both_stores_after_the_move
    plastic("migrate", "stores")

    assert_equal 0, plastic("status")
    assert_match(/^global  1 active/, @fixture.printed)
    assert_match(/^acme    1 active/, @fixture.printed)
  end

  def test_the_doctor_finds_the_index_links_after_the_move
    seed("store/1--alpha/1--alpha.md", "# Alpha\n")
    plastic("migrate", "stores")
    ghosts = Doctor.new(plastic_home: home).check_global_store.find { |result| result[:name] == "ghost_references" }

    assert_equal "pass", ghosts[:status]
  end

  def test_a_second_run_exits_three
    plastic("migrate", "stores")

    assert_equal 3, plastic("migrate", "stores")
    assert_includes @fixture.warned, "stores/"
  end

  def test_a_held_lock_exits_three_and_changes_nothing
    seed("projects/acme/store/2--beta/delivery.lock", "held\n")

    assert_equal 3, plastic("migrate", "stores")
    assert_includes @fixture.warned, "projects/acme/store/2--beta/delivery.lock"
    refute_path_exists File.join(home, "stores")
  end

  def test_a_stale_lock_does_not_block_the_move
    seed("store/1--alpha/delivery.lock", "held\n")
    File.utime(Time.now - 7200, Time.now - 7200, File.join(home, "store/1--alpha/delivery.lock"))

    assert_equal 0, plastic("migrate", "stores")
  end

  def test_an_existing_copy_exits_three_and_changes_nothing
    FileUtils.mkdir_p(copy)

    assert_equal 3, plastic("migrate", "stores")
    assert_includes @fixture.warned, copy
    refute_path_exists File.join(home, "stores")
  end

  def test_a_home_with_no_qmd_index_still_moves
    File.delete(qmd_index)

    assert_equal 0, plastic("migrate", "stores")
    refute_includes @fixture.printed, "index.yml"
  end

  def test_the_bare_group_lists_the_stores_subcommand
    assert_equal 0, plastic("migrate")
    assert_includes @fixture.printed, "migrate stores"
  end
end
