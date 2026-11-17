# frozen_string_literal: true

require_relative "../../commands/installer_helper"
require_relative "../../doctor/whole_home"
require_relative "../../../../lib/plastic/workflows/code/doctor"
require_relative "../../../../lib/plastic/graph/evidence/writer"

class CheckHealthTest < Plastic::TestCase
  include InstallerHelper
  include WholeHome

  GATE = "a check found a problem; run the repairs named above, then run plastic doctor again"

  def setup
    super
    whole_home
  end

  def facts_for(env, session) = { harness: scoped_harness(session:, env: { "PLASTIC_PACKAGE_ROOT" => fake_package(RUNNING) }.merge(env)), harness_name: nil }

  def check(env = { "CLAUDE_CODE_SESSION_ID" => "s-1" }, session: "s-1") = run_workflow(Plastic::Workflows::Code::Doctor, **facts_for(env, session))

  def failed_check(env = { "CLAUDE_CODE_SESSION_ID" => "s-1" }, session: "s-1") = stop_workflow(Plastic::Workflows::Code::Doctor, **facts_for(env, session))

  def test_a_whole_home_is_done_with_no_repair
    outcome, context = check

    assert_equal [:done, nil], [outcome, printed_row(context, "repair:")]
  end

  def test_each_check_prints_one_row
    _outcome, context = check

    assert_equal "version:", printed_rows(context).first.first
  end

  def test_a_finding_fails_at_the_gate
    File.delete(machine_path)

    assert_equal GATE, assert_raises(Plastic::Failed) { check }.message
  end

  def test_the_repairs_print_as_one_row_with_one_line_each
    File.delete(File.join(claude_dir, "plastic", "VERSION"))
    File.chmod(0o644, hook_file)

    assert_equal ["plastic init", "plastic install --reinstall"], printed_row(failed_check.last, "repair:")
  end

  def test_a_codex_session_with_no_install_reports_the_missing_record
    error, context = failed_check({ "CODEX_THREAD_ID" => "t-1" }, session: "t-1")

    assert_equal GATE, error.message
    assert_includes printed_row(context, "codex record:"), "no installation record"
  end

  def test_a_store_whose_search_rows_match_the_passages_prints_in_step
    write_evidence(SLUG)

    assert_equal "ok, in step", printed_row(check.last, "search index #{SLUG}:")
  end

  def test_each_store_prints_its_own_search_index_row
    labels = printed_rows(check.last).map(&:first).grep(/\Asearch index/)

    assert_equal ["search index global:", "search index #{SLUG}:"], labels
  end

  def test_search_rows_out_of_step_are_rebuilt_and_the_row_says_so
    write_evidence(SLUG)
    derived(SLUG).transaction { |batch| batch.add("DELETE FROM document_fts") }
    outcome, context = check

    assert_equal [:done, "ok, rebuilt", 1], [outcome, printed_row(context, "search index #{SLUG}:"), search_rows(SLUG)]
  end

  def test_evidence_that_is_gone_fails_with_the_backup_list_to_read
    write_evidence(SLUG)
    knowledge(SLUG).transaction { |batch| batch.add("DELETE FROM document_revisions") }
    error, context = failed_check

    assert_equal [GATE, "the evidence of 1 document is lost; no rebuild brings it back", ["plastic backup list --store #{SLUG}"]],
      [error.message, printed_row(context, "search index #{SLUG}:"), printed_row(context, "repair:").grep(/backup list/)]
  end

  def test_a_store_with_no_knowledge_database_prints_that_and_makes_none
    Plastic::Graph::Database::ConnectionPool.release(@home)
    File.delete(store_path(:knowledge))
    _error, context = failed_check

    assert_equal ["ok, no database in this store", false], [printed_row(context, "search index #{SLUG}:"), File.exist?(store_path(:knowledge))]
  end

  def test_the_start_hook_check_leaves_the_search_rows_as_they_are
    write_evidence(SLUG)
    derived(SLUG).transaction { |batch| batch.add("DELETE FROM document_fts") }
    harness = scoped_harness(session: "s-1", env: { "PLASTIC_PACKAGE_ROOT" => fake_package(RUNNING), "CLAUDE_CODE_SESSION_ID" => "s-1" })
    Plastic::Doctor.failing(harness.scope, harness: "claude-code", running: RUNNING, now: FixedClock::AT)

    assert_equal 0, search_rows(SLUG)
  end

  private

  def knowledge(store) = Plastic::Graph.open(home: @plastic_home, store:).databases.fetch(:store)

  def derived(store) = Plastic::Graph.open(home: @plastic_home, store:).databases.fetch(:store)

  def write_evidence(store)
    origin_id = Plastic::Graph::Origin.new(@plastic_home).id
    Plastic::Graph::Retrieval::Evidence::Writer.new(knowledge(store), origin_id, clock: FixedClock::CLOCK).write("1", "plan.md", "Doctor evidence\n")
    Plastic::Graph::Retrieval::Index.new(knowledge(store), origin_id).rebuild
  end

  def search_rows(store) = derived(store).row("SELECT count(*) AS n FROM document_fts").fetch("n")
end
