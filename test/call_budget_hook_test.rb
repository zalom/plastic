# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "time"

# scripts/hook-call-budget carries no .rb extension (every hook script in
# this tree is a direct executable), so it is brought in with `load`, not
# `require_relative`: the trailing `if $PROGRAM_NAME == __FILE__` guard in
# the file means loading it here defines HookCallBudget without touching
# stdin, ENV, or exit - see that file's own docstring.
load File.expand_path("../scripts/hook-call-budget", __dir__)

# HookCallBudget (intent 355, n2): the PreToolUse call budget hook. Matrix
# rows 2.5-2.9 and 2.11 in the node's own failure-mode matrix (2.1-2.4 live
# in runner_policy_test.rb/runner_dispatch_test.rb/node_packet_budget_test.rb,
# 2.10 in runner_absorb_test.rb, 2.12 in install_sync_test.rb).
class CallBudgetHookTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("call-budget-home")
    @store = File.join(@home, "store")
    FileUtils.mkdir_p(@store)
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  def write_lease(session:, cap: 60, holder: nil, delegates: [], node: "n1", intent: "1--demo")
    holder ||= session
    intent_dir = File.join(@store, intent)
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "#{intent}.md"), "# Demo\n")
    File.write(File.join(intent_dir, "delivery.lock"),
               JSON.generate("owner_session" => holder, "delegates" => delegates, "type" => "delivery"))
    File.write(File.join(intent_dir, "savepoint.md"), <<~LEDGER)
      2026-01-01T00:00:00Z  #{node}  running holder=#{holder} expires=2026-01-01T01:00:00Z packet=abc model=sonnet calls=#{cap}
    LEDGER
    intent_dir
  end

  def transcript_with(tool_use_counts)
    path = File.join(@home, "transcript-#{rand(1_000_000)}.jsonl")
    File.open(path, "w") do |f|
      f.puts JSON.generate("type" => "user", "message" => { "content" => "hi" })
      tool_use_counts.each do |n|
        blocks = [{ "type" => "text", "text" => "ok" }] + Array.new(n) { |i| { "type" => "tool_use", "id" => "t#{i}" } }
        f.puts JSON.generate("type" => "assistant", "message" => { "content" => blocks })
      end
    end
    path
  end

  # --- 2.5: counts tool_use blocks in the transcript the hook input names ----

  def test_counts_tool_use_blocks_in_transcript
    path = transcript_with([1, 1, 2, 0])
    assert_equal 4, HookCallBudget.count_tool_use_blocks(path)
  end

  def test_counts_are_never_confused_with_the_hooks_own_invocations
    # The count comes ONLY from the named transcript file's own content -
    # calling count_tool_use_blocks itself many times over the same fixture
    # never inflates what any one call reports.
    path = transcript_with([1, 1])
    3.times { HookCallBudget.count_tool_use_blocks(path) }
    assert_equal 2, HookCallBudget.count_tool_use_blocks(path)
  end

  # --- 2.6: no lease means no cap, never a cap of zero -----------------------

  def test_no_lease_means_no_cap
    assert_nil HookCallBudget.find_lease("stranger-session", plastic_home: @home)

    path = transcript_with(Array.new(500, 1))
    payload = { "session_id" => "stranger-session", "transcript_path" => path }
    assert_nil HookCallBudget.decide(payload, plastic_home: @home),
               "a session with no lease anywhere must never be capped, let alone at zero"
  end

  # --- 2.6b: a delegate of the holder is authorized the same as the holder --

  def test_delegate_of_the_holder_finds_the_same_lease
    write_lease(session: "owner-1", cap: 5, delegates: ["delegate-1"])
    lease = HookCallBudget.find_lease("delegate-1", plastic_home: @home)
    refute_nil lease
    assert_equal 5, lease[:cap]
    assert_equal "n1", lease[:node]
  end

  # --- 2.7: past the cap, the hook denies with the commit-and-return instruction --

  def test_past_cap_denies_with_return_instruction
    write_lease(session: "owner-2", cap: 2, node: "n2")
    path = transcript_with([1, 1, 1])
    payload = { "session_id" => "owner-2", "transcript_path" => path }

    result = HookCallBudget.decide(payload, plastic_home: @home)
    refute_nil result
    reason = result.dig("hookSpecificOutput", "permissionDecisionReason")
    assert_equal "deny", result.dig("hookSpecificOutput", "permissionDecision")
    assert_equal "PreToolUse", result.dig("hookSpecificOutput", "hookEventName")
    assert_includes reason, "n2"
    assert_includes reason, "commit what is green and return failed_verification reason=call_budget"
  end

  def test_at_or_under_cap_allows
    write_lease(session: "owner-3", cap: 3, node: "n3")
    path = transcript_with([1, 1, 1])
    payload = { "session_id" => "owner-3", "transcript_path" => path }

    assert_nil HookCallBudget.decide(payload, plastic_home: @home)
  end

  # --- 2.8: under the cap, the hook allows fast on a 3 MB transcript ---------

  def test_under_cap_allows_fast
    write_lease(session: "owner-4", cap: 100_000, node: "n4")
    path = File.join(@home, "big-transcript.jsonl")
    File.open(path, "w") do |f|
      line = JSON.generate("type" => "assistant",
                            "message" => { "content" => [{ "type" => "text", "text" => "x" * 1500 }] })
      target = 3 * 1024 * 1024
      written = 0
      while written < target
        f.puts(line)
        written += line.bytesize + 1
      end
    end
    assert_operator File.size(path), :>=, 3 * 1024 * 1024, "fixture assumption: the transcript must be >= 3 MB"

    payload = { "session_id" => "owner-4", "transcript_path" => path }
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = HookCallBudget.decide(payload, plastic_home: @home)
    elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000

    assert_nil result
    assert_operator elapsed_ms, :<, 50, "scanning a 3 MB transcript must stay under 50 ms, took #{elapsed_ms}ms"
  end

  # --- 2.9: an unreadable transcript fails open and writes a ledger line -----

  def test_unreadable_transcript_fails_open_with_ledger_line
    intent_dir = write_lease(session: "owner-5", cap: 10, node: "n5")
    unreadable = File.join(@home, "not-a-file-dir")
    FileUtils.mkdir_p(unreadable) # a directory can never be read as a transcript

    payload = { "session_id" => "owner-5", "transcript_path" => unreadable }
    result = HookCallBudget.decide(payload, plastic_home: @home)

    assert_nil result, "an unreadable transcript must fail open (allow), never deny"
    savepoint = File.read(File.join(intent_dir, "savepoint.md"))
    assert_includes savepoint, "CallBudget", "an unreadable transcript must leave a ledger line, not a silent gap"
    assert_includes savepoint, "owner-5"
  end

  # --- 2.11: hooks.json registers the hook on PreToolUse for every tool -----

  def test_registered_in_hooks_json
    raw = JSON.parse(File.read(File.expand_path("../hooks/hooks.json", __dir__)))
    groups = raw.dig("hooks", "PreToolUse")
    refute_nil groups, "PreToolUse must be registered in hooks.json"
    assert_equal 1, groups.size
    assert_equal "", groups.first["matcher"], "matcher must be empty (every tool), not scoped to a subset"
    commands = groups.first["hooks"].map { |h| h["command"] }
    assert commands.any? { |c| c.include?("call-budget") }, commands.inspect
  end
end
