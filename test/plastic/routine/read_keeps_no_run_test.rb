# frozen_string_literal: true

require_relative "../../test_helper"

class ReadKeepsNoRunTest < Plastic::TestCase
  include LifecycleHelper
  include BackupHomes

  def runs(home = @plastic_home, store = "global")
    Plastic::Graph.open(home:, store:).databases.fetch(:local).row("SELECT COUNT(*) AS n FROM routine_runs").fetch("n")
  end

  def added_by(&call)
    before = runs
    call.call
    runs - before
  end

  def test_intent_show_keeps_no_routine_run_row
    open_intent

    assert_equal 0, added_by { cli("intent", "show", "1") }
  end

  def test_intent_brief_keeps_no_routine_run_row
    open_intent

    assert_equal 0, added_by { cli("intent", "brief", "1") }
  end

  def test_search_keeps_no_routine_run_row
    open_intent

    assert_equal 0, added_by { cli("search", "alpha") }
  end

  def test_backup_list_keeps_no_routine_run_row
    home = fresh_home
    before = runs(home, "alpha")
    list_call(home, "--store", "alpha")

    assert_equal before, runs(home, "alpha")
  end

  def test_a_real_backup_keeps_one_routine_run_row
    home = fresh_home
    before = runs(home, "alpha")
    result = backup_call(home, "--store", "alpha")

    assert_equal 0, result.code, result.err
    assert_equal before + 1, runs(home, "alpha")
  end

  def test_a_dry_run_backup_keeps_no_routine_run_row
    home = fresh_home
    before = runs(home, "alpha")
    backup_call(home, "--store", "alpha", "--dry-run")

    assert_equal before, runs(home, "alpha")
  end

  def test_node_add_keeps_exactly_one_routine_run_row
    specified
    cli("intent", "approve", "1")
    cli("auto", "1")

    assert_equal 1, added_by { cli("node", "add", "1", "Deliver it", "--criterion", KEY) }
  end

  def test_intent_revise_keeps_one_routine_run_row
    open_intent

    assert_equal 1, added_by { cli("intent", "revise", "1", "Beta") }
  end

  def test_intent_revise_dry_run_keeps_no_routine_run_row
    open_intent

    assert_equal 0, added_by { cli("intent", "revise", "1", "Beta", "--dry-run") }
  end
end
