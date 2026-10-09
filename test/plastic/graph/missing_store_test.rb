# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../commands/installer_helper"
require "json"
require "shellwords"
require_relative "../../../scripts/lib/plastic/cli/projects_file"
require_relative "../../../scripts/lib/plastic/graph/retrieval/source"

class MissingStoreTest < Plastic::TestCase
  include Plastic::TestCase::PreviewHelper

  def test_reading_a_registered_project_with_no_store_fails_and_makes_nothing
    with_home do |home|
      register(home, "fresh")

      call = call_in(home, "intent", "show", "1", "--project", "fresh")

      assert_equal 1, call.code
      assert_includes call.out, "next: plastic project new fresh #{File.join(File.dirname(home), "fresh")}"
      refute_path_exists File.join(home, "stores", "fresh")
    end
  end

  def test_the_line_for_a_registered_project_runs_as_written_and_makes_its_store
    with_home do |home|
      register(home, "fresh")
      line = call_in(home, "intent", "show", "1", "--project", "fresh").out[/^next: (.*)$/, 1]

      assert_equal 0, call_in(home, *Shellwords.split(line).drop(1)).code
      assert_path_exists File.join(home, "stores", "fresh")
    end
  end

  def test_an_unregistered_project_keeps_the_path_placeholder
    with_home do |home|
      call = call_in(home, "intent", "show", "1", "--project", "nowhere")

      assert_equal 2, call.code
      refute_includes call.out, "project new nowhere /"
    end
  end

  def test_a_search_in_a_project_with_no_store_makes_nothing
    with_home do |home|
      register(home, "fresh")

      call = call_in(home, "search", "anything", "--project", "fresh")

      assert_equal 1, call.code
      refute_path_exists File.join(home, "stores", "fresh")
    end
  end

  def test_reading_with_no_global_store_names_the_install_and_makes_nothing
    with_home(global: false) do |home|
      call = call_in(home, "intent", "show", "1")

      assert_equal 1, call.code
      assert_includes call.out, "next: plastic install --reinstall"
      refute_path_exists File.join(home, "stores")
    end
  end

  def test_project_new_leaves_a_store_where_an_intent_can_be_opened
    with_home do |home|
      Plastic::Graph.create(home:, store: "global")
      folder = File.join(File.dirname(home), "repo")
      FileUtils.mkdir_p(folder)

      assert_equal 0, call_in(home, "project", "new", "fresh", folder).code
      assert_equal 0, call_in(home, "intent", "new", "Alpha", "--project", "fresh").code
    end
  end

  def test_the_hooks_exit_quietly_and_make_nothing_when_the_store_is_missing
    with_home(global: false) do |home|
      event = JSON.generate(session_id: "s-1", cwd: home)

      %w[record resume].each do |name|
        call = plastic("hook", name, input: event, env: { "PLASTIC_HOME" => home }, table: Plastic::CLI::TABLE)

        assert_equal [0, "", ""], [call.code, call.out, call.err], name
      end
      refute_path_exists File.join(home, "stores")
    end
  end

  def test_status_lists_the_stores_it_can_read_when_one_has_no_folder
    with_home(global: false) do |home|
      Plastic::Graph.create(home:, store: "other")

      call = call_in(home, "status")

      assert_equal 0, call.code
      assert_match(/store:\s+other/, call.out)
    end
  end

  def test_create_makes_a_store_that_opens_and_open_refuses_one_that_is_missing
    with_home(global: false) do |home|
      assert_raises(Plastic::Graph::MissingStore) { Plastic::Graph.open(home:, store: "fresh") }
      assert_raises(Plastic::Graph::MissingStore) { Plastic::Graph.open_retrieval(home:, store: "fresh") }

      Plastic::Graph.create(home:, store: "fresh")

      assert_equal [], Plastic::Graph.open(home:, store: "fresh").retrieval.intents
    end
  end

  private

  def register(home, slug)
    folder = File.join(File.dirname(home), slug)
    FileUtils.mkdir_p(folder)
    Plastic::CLI::ProjectsFile.new(File.join(home, "projects.yml")).add(slug, folder)
  end
end

class MissingGlobalStoreRepairTest < Plastic::TestCase
  include InstallerHelper

  def test_the_install_line_next_prints_for_a_missing_global_store_runs_and_makes_the_store
    installed_home_without_stores

    stopped = call("intent", "show", "1")
    line = stopped.out[/^next: (.*)$/, 1]
    repaired = call(*line.split.drop(1))

    assert_equal [1, "plastic install --reinstall", 0], [stopped.code, line, repaired.code], repaired.err
    assert_path_exists File.join(@plastic_home, "stores", "global")
  end
end
