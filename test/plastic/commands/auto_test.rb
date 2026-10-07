# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/auto"

class AutoTest < Plastic::TestCase
  include RoadmapHelper

  CLEAR_SPEC = "# Spec\n\n## Done criteria\n- ships\n\n## Open Questions\n- none\n"

  def call(*args, env: {}) = plastic("auto", *args, env: { "PLASTIC_SESSION" => "s-1" }.merge(env), table: Plastic::CLI::TABLE)

  def write_spec(intent, text)
    write("#{intent.dir}/spec.md", text)
    plastic("sync", "up", table: Plastic::CLI::TABLE)
  end

  def clear_intent
    intent = open_intent
    write_spec(intent, CLEAR_SPEC)
    intent
  end

  def register_repo(path = File.join(@home, "repo"))
    File.write(File.join(@plastic_home, "projects.yml"), "projects:\n  global:\n    path: #{path}\n")
    path
  end

  def next_line(result) = result.out.lines(chomp: true).find { |line| line.start_with?("next: ") }

  def lock_rows = store_graphs.databases.fetch(:local).rows("SELECT * FROM locks")

  def expire_lock
    store_graphs.databases.fetch(:local).transaction do |batch|
      batch.add("UPDATE locks SET renewed_at = '2000-01-01T00:00:00Z'")
    end
  end

  def active_intent
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Done criteria\n- ships\n")
    store_graphs.work.activate_intent(intent.intent_id)
    intent
  end

  def test_a_clear_spec_goes_active_and_takes_the_lock
    intent = clear_intent

    result = call(intent.intent_id)

    lock = retrieval.lock(intent.intent_id)

    assert_equal [0, "active", "s-1", "auto"], [result.code, retrieval.intent(intent.intent_id).status, lock.session_id, lock.mode]
    assert_includes result.out, "next: plastic intent brief #{intent.intent_id}"
    assert_empty result.err
  end

  def test_an_open_decision_refuses_and_the_status_stays_open
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Done criteria\n- ships\n\n## Open Questions\n- which store wins\n")

    result = call(intent.intent_id)

    assert_equal [3, "open"], [result.code, retrieval.intent(intent.intent_id).status]
    assert_includes result.err, "intent 1 has an open decision; run plastic intent spec 1"
  end

  def test_no_done_criteria_refuses
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Open Questions\n- none\n")

    result = call(intent.intent_id)

    assert_equal 3, result.code
    assert_includes result.err, "intent 1 names no done criterion"
  end

  def test_another_sessions_live_lock_refuses_and_is_kept
    intent = clear_intent
    store_graphs.work.take_lock(intent.intent_id, session_id: "s-2", mode: "auto")

    result = call(intent.intent_id)

    assert_equal [3, "s-2"], [result.code, retrieval.lock(intent.intent_id).session_id]
    assert_includes result.err, "intent 1 is locked by session s-2"
  end

  def test_a_done_intent_refuses
    open_intent
    store_graphs.databases.fetch(:work).transaction do |batch|
      batch.write(:intents, "UPDATE intents SET status = 'done' WHERE intent_id = :intent_id", intent_id: "1")
    end

    result = call("1")

    assert_equal 3, result.code
    assert_includes result.err, "intent 1 is done"
  end

  def test_a_call_with_no_session_fails
    intent = clear_intent

    result = call(intent.intent_id, env: { "PLASTIC_SESSION" => "" })

    assert_equal [1, []], [result.code, lock_rows]
    assert_includes result.err, "plastic auto names no session"
  end

  def test_two_ids_exit_2_and_write_no_lock
    clear_intent
    write_spec(open_intent("Beta"), CLEAR_SPEC)

    result = call("1", "2")

    assert_equal [2, [], %w[open open]], [result.code, lock_rows, %w[1 2].map { |id| retrieval.intent(id).status }]
    assert_includes result.err, "unexpected 2"
  end

  def test_no_id_exits_2
    result = call

    assert_equal [2, ""], [result.code, result.out]
    assert_includes result.err, "missing"
  end

  def test_a_missing_intent_fails
    result = call("9")

    assert_equal [1, []], [result.code, lock_rows]
    assert_includes result.err, "no intent 9 in this store"
  end

  def test_the_old_start_word_is_a_usage_error
    clear_intent

    result = call("start", "1")

    assert_equal [2, [], "open"], [result.code, lock_rows, retrieval.intent("1").status]
  end

  def test_auto_start_alone_reads_start_as_a_roadmap
    result = call("start")

    assert_equal [1, []], [result.code, lock_rows]
    assert_includes result.err, "no roadmap start"
  end

  def test_an_intent_shaped_slug_reads_as_an_intent
    store_graphs.work.write_batch("2026", 1, fields: roadmap_fields("T", goal: "G", done: "d"))

    result = call("2026")

    assert_equal 1, result.code
    assert_includes result.err, "no intent 2026 in this store"
  end

  def test_an_unknown_roadmap_fails
    result = call("r9")

    assert_equal [1, []], [result.code, lock_rows]
    assert_includes result.err, "no roadmap r9"
  end

  def test_a_roadmap_arms_its_in_flight_item
    roadmap
    item("a")
    intent_id, = store_graphs.work.start_roadmap_item("r1", "a")

    result = call("r1")

    assert_equal [0, "s-1", "active"], [result.code, retrieval.lock(intent_id)&.session_id, retrieval.intent(intent_id).status]
  end

  def test_a_roadmap_with_a_ready_item_offers_roadmap_start
    roadmap
    item("a")

    result = call("r1")

    assert_equal [0, [], "next: plastic roadmap start r1 a --project global"], [result.code, lock_rows, next_line(result)]
  end

  def test_a_resumed_roadmap_call_never_arms_a_stale_intent
    roadmap
    item("a")
    item("b")
    store_graphs.work.start_roadmap_item("r1", "a")
    failed = call("r1", env: { "PLASTIC_SESSION" => "" })
    store_graphs.work.drop_item("r1", "a")

    result = call("r1")

    assert_equal [1, 0, [], "next: plastic roadmap start r1 b --project global"], [failed.code, result.code, lock_rows, next_line(result)]
  end

  def test_a_registered_repo_prints_the_worktree_command_as_next
    repo = register_repo
    intent = clear_intent

    result = call(intent.intent_id)

    worktree = File.join(repo, ".claude", "worktrees", "1--alpha")

    assert_equal 0, result.code
    assert_includes result.out, "worktree: #{worktree}\n"
    assert_includes result.out, "branch: plastic/1--alpha\n"
    assert_equal "next: git -C #{repo} worktree add #{worktree} -b plastic/1--alpha", next_line(result)
  end

  def test_an_existing_worktree_offers_the_brief
    repo = register_repo
    intent = clear_intent
    FileUtils.mkdir_p(File.join(repo, ".claude", "worktrees", "1--alpha"))

    result = call(intent.intent_id)

    assert_equal [0, "next: plastic intent brief 1 --project global"], [result.code, next_line(result)]
  end

  def test_a_store_with_no_registered_repo_prints_no_worktree
    intent = clear_intent

    result = call(intent.intent_id)

    assert_equal 0, result.code
    refute_includes result.out, "worktree:"
  end

  def test_a_rerun_exits_0_and_prints_the_worktree_again
    register_repo
    intent = clear_intent
    call(intent.intent_id)

    result = call(intent.intent_id)

    assert_equal [0, "s-1"], [result.code, retrieval.lock(intent.intent_id).session_id]
    assert_includes result.out, "worktree: "
  end

  def test_an_active_intent_without_a_lock_takes_one
    intent = active_intent

    result = call(intent.intent_id)

    lock = retrieval.lock(intent.intent_id)

    assert_equal [0, "s-1", "auto", true], [result.code, lock&.session_id, lock&.mode, lock&.live?]
  end

  def test_an_expired_foreign_lock_is_taken_over
    intent = active_intent
    store_graphs.work.take_lock(intent.intent_id, session_id: "s-2", mode: "auto")
    expire_lock

    result = call(intent.intent_id)

    lock = retrieval.lock(intent.intent_id)

    assert_equal [0, "s-1", true], [result.code, lock.session_id, lock.live?]
  end
end
