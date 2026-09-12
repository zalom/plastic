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

# HookCallBudget (intent 355, n2, review fix n8). Matrix rows 2.5-2.9 and
# 2.11 in the node's own failure-mode matrix (2.1-2.4 live in
# runner_policy_test.rb/runner_dispatch_test.rb/node_packet_budget_test.rb,
# 2.10 in runner_absorb_test.rb, 2.12 in install_sync_test.rb).
#
# Inside a subagent the hook input's session_id and transcript_path are the
# MAIN session's, never the subagent's own, so the cap is keyed on agent_id
# and reads the subagent's OWN transcript (at
# <dirname(transcript_path)>/<session_id>/subagents/agent-<agent_id>.jsonl),
# whose first user record names the node's packet path.
class CallBudgetHookTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir("call-budget-home")
    @store = File.join(@home, "store")
    FileUtils.mkdir_p(@store)
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  def write_running_line(intent_dir, node, cap:)
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "savepoint.md"), <<~LEDGER)
      2026-01-01T00:00:00Z  #{node}  running holder=auto-1 expires=2026-01-01T01:00:00Z packet=abc model=sonnet calls=#{cap}
    LEDGER
  end

  def main_transcript_path
    File.join(@home, "main.jsonl")
  end

  def subagent_transcript_path(session_id, agent_id)
    File.join(@home, session_id, "subagents", "agent-#{agent_id}.jsonl")
  end

  def write_subagent_transcript(session_id:, agent_id:, prompt:, tool_use_counts: [])
    path = subagent_transcript_path(session_id, agent_id)
    FileUtils.mkdir_p(File.dirname(path))
    File.open(path, "w") do |f|
      f.puts JSON.generate("type" => "user", "message" => { "content" => prompt })
      tool_use_counts.each do |n|
        blocks = [{ "type" => "text", "text" => "ok" }] + Array.new(n) { |i| { "type" => "tool_use", "id" => "t#{i}" } }
        f.puts JSON.generate("type" => "assistant", "message" => { "content" => blocks })
      end
    end
    path
  end

  def packet_prompt(intent_dir, node)
    "Your packet: #{intent_dir}/packets/#{node}--a1.packet (read it only if something is unclear)"
  end

  def payload(session_id:, agent_id: nil, extra: {})
    base = { "session_id" => session_id, "transcript_path" => main_transcript_path }
    base["agent_id"] = agent_id if agent_id
    base.merge(extra)
  end

  # --- helpers used only by count_tool_use_blocks (unit-level, no lease) ----

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

  # --- pure count_tool_use_blocks -------------------------------------------

  def test_counts_tool_use_blocks_in_transcript
    path = transcript_with([1, 1, 2, 0])
    assert_equal 4, HookCallBudget.count_tool_use_blocks(path)
  end

  def test_counts_are_never_confused_with_the_hooks_own_invocations
    path = transcript_with([1, 1])
    3.times { HookCallBudget.count_tool_use_blocks(path) }
    assert_equal 2, HookCallBudget.count_tool_use_blocks(path)
  end

  # --- 2.6: no agent_id (the main thread) is never capped -------------------

  def test_no_agent_id_means_no_cap
    intent_dir = File.join(@store, "999--demo")
    write_running_line(intent_dir, "n1", cap: 1)
    write_subagent_transcript(session_id: "main-sess", agent_id: "agent-1",
                               prompt: packet_prompt(intent_dir, "n1"), tool_use_counts: Array.new(500, 1))

    assert_nil HookCallBudget.decide(payload(session_id: "main-sess")),
               "a call with no agent_id must never be capped, no matter what the subagent transcript holds"
  end

  # --- no packet path in the first prompt means allow ------------------------

  def test_no_packet_path_in_first_prompt_means_allow
    write_subagent_transcript(session_id: "main-sess", agent_id: "agent-1",
                               prompt: "no packet path in this prompt at all", tool_use_counts: Array.new(500, 1))

    assert_nil HookCallBudget.decide(payload(session_id: "main-sess", agent_id: "agent-1"))
  end

  # --- B1/B2: keyed on agent_id, counted from the subagent's own transcript -

  def test_subagent_capped_by_agent_id_and_packet_path
    intent_dir = File.join(@store, "999--demo")
    write_running_line(intent_dir, "n8", cap: 60)
    write_subagent_transcript(session_id: "main-sess-uuid", agent_id: "agent-77",
                               prompt: packet_prompt(intent_dir, "n8"), tool_use_counts: Array.new(61, 1))

    result = HookCallBudget.decide(payload(session_id: "main-sess-uuid", agent_id: "agent-77"))

    refute_nil result,
               "a subagent past its node's cap must be denied even though the hook input's " \
               "session_id and transcript_path are the main session's, never the subagent's own"
    assert_equal "deny", result.dig("hookSpecificOutput", "permissionDecision")
    assert_includes result.dig("hookSpecificOutput", "permissionDecisionReason"), "n8"
  end

  def test_counts_the_subagent_transcript_not_the_main
    intent_dir = File.join(@store, "999--demo")
    write_running_line(intent_dir, "n8", cap: 10)
    File.open(main_transcript_path, "w") do |f|
      blocks = Array.new(200) { |i| { "type" => "tool_use", "id" => "m#{i}" } }
      f.puts JSON.generate("type" => "assistant", "message" => { "content" => blocks })
    end
    write_subagent_transcript(session_id: "main-sess", agent_id: "agent-5",
                               prompt: packet_prompt(intent_dir, "n8"), tool_use_counts: [5])

    assert_nil HookCallBudget.decide(payload(session_id: "main-sess", agent_id: "agent-5")),
               "the count must come from the subagent's own transcript (5 blocks), " \
               "never the main transcript (200 blocks)"
  end

  # --- B3/D3: past the cap, a plain git commit is still allowed -------------

  def test_git_commit_allowed_past_cap
    intent_dir = File.join(@store, "999--demo")
    write_running_line(intent_dir, "n8", cap: 2)
    write_subagent_transcript(session_id: "main-sess", agent_id: "agent-9",
                               prompt: packet_prompt(intent_dir, "n8"), tool_use_counts: [5])

    base = payload(session_id: "main-sess", agent_id: "agent-9")

    git_payload = base.merge("tool_name" => "Bash",
                              "tool_input" => { "command" => "git -C #{intent_dir} commit -F /tmp/msg.txt" })
    assert_nil HookCallBudget.decide(git_payload),
               "a plain git commit past the cap must still be allowed (D3), or the denial " \
               "could never commit what it just told the executor to commit"

    plain_git_payload = base.merge("tool_name" => "Bash", "tool_input" => { "command" => "git add file.rb" })
    assert_nil HookCallBudget.decide(plain_git_payload)

    other_payload = base.merge("tool_name" => "Bash", "tool_input" => { "command" => "rm -rf /tmp/whatever" })
    refute_nil HookCallBudget.decide(other_payload),
               "a non-git Bash call past the cap must still be denied"

    chained_payload = base.merge("tool_name" => "Bash",
                                  "tool_input" => { "command" => "git commit -F /tmp/msg.txt && rm -rf /tmp" })
    refute_nil HookCallBudget.decide(chained_payload),
               "a chained command riding on a leading git verb must still be denied"
  end

  # --- B5: only THIS node's latest ledger line decides the cap --------------

  def test_node_with_later_done_line_is_not_capped
    intent_dir = File.join(@store, "999--demo")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "savepoint.md"), <<~LEDGER)
      2026-01-01T00:00:00Z  n1  running holder=auto-1 expires=2026-01-01T01:00:00Z packet=abc model=sonnet calls=2
      2026-01-01T00:05:00Z  n1  done gates=integrity commit=abc123
    LEDGER
    write_subagent_transcript(session_id: "main-sess", agent_id: "agent-1",
                               prompt: packet_prompt(intent_dir, "n1"), tool_use_counts: [5, 5, 5])

    assert_nil HookCallBudget.decide(payload(session_id: "main-sess", agent_id: "agent-1")),
               "a node whose latest ledger line is done must never be capped by an earlier running line"
  end

  def test_sibling_node_running_does_not_cap_this_node
    intent_dir = File.join(@store, "999--demo")
    FileUtils.mkdir_p(intent_dir)
    File.write(File.join(intent_dir, "savepoint.md"), <<~LEDGER)
      2026-01-01T00:00:00Z  n1  running holder=auto-1 expires=2026-01-01T01:00:00Z packet=abc model=sonnet calls=2
      2026-01-01T00:05:00Z  n1  done gates=integrity commit=abc123
      2026-01-01T00:06:00Z  n2  running holder=auto-2 expires=2026-01-01T01:00:00Z packet=abc model=sonnet calls=10
    LEDGER
    write_subagent_transcript(session_id: "main-sess", agent_id: "agent-1",
                               prompt: packet_prompt(intent_dir, "n1"), tool_use_counts: [5, 5, 5])

    assert_nil HookCallBudget.decide(payload(session_id: "main-sess", agent_id: "agent-1")),
               "a sibling node's own running line must never cap this subagent's node"
  end

  # --- 2.7: past the cap, the hook denies with the commit-and-return instruction --

  def test_past_cap_denies_with_return_instruction
    intent_dir = File.join(@store, "999--demo")
    write_running_line(intent_dir, "n2", cap: 2)
    write_subagent_transcript(session_id: "main-sess", agent_id: "agent-2",
                               prompt: packet_prompt(intent_dir, "n2"), tool_use_counts: [1, 1, 1])

    result = HookCallBudget.decide(payload(session_id: "main-sess", agent_id: "agent-2"))
    refute_nil result
    reason = result.dig("hookSpecificOutput", "permissionDecisionReason")
    assert_equal "deny", result.dig("hookSpecificOutput", "permissionDecision")
    assert_equal "PreToolUse", result.dig("hookSpecificOutput", "hookEventName")
    assert_includes reason, "n2"
    assert_includes reason, "commit what is green and return failed_verification reason=call_budget"
  end

  def test_at_or_under_cap_allows
    intent_dir = File.join(@store, "999--demo")
    write_running_line(intent_dir, "n3", cap: 3)
    write_subagent_transcript(session_id: "main-sess", agent_id: "agent-3",
                               prompt: packet_prompt(intent_dir, "n3"), tool_use_counts: [1, 1, 1])

    assert_nil HookCallBudget.decide(payload(session_id: "main-sess", agent_id: "agent-3"))
  end

  # --- 2.8: under the cap, the hook allows fast on a 3 MB subagent transcript --

  def test_under_cap_allows_fast
    intent_dir = File.join(@store, "999--demo")
    write_running_line(intent_dir, "n4", cap: 100_000)

    path = subagent_transcript_path("main-sess", "agent-4")
    FileUtils.mkdir_p(File.dirname(path))
    File.open(path, "w") do |f|
      f.puts JSON.generate("type" => "user", "message" => { "content" => packet_prompt(intent_dir, "n4") })
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

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = HookCallBudget.decide(payload(session_id: "main-sess", agent_id: "agent-4"))
    elapsed_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000

    assert_nil result
    assert_operator elapsed_ms, :<, 50, "scanning a 3 MB subagent transcript must stay under 50 ms, took #{elapsed_ms}ms"
  end

  # --- 2.9: an unreadable transcript fails open and writes a ledger line -----

  def test_unreadable_transcript_fails_open_with_ledger_line
    intent_dir = File.join(@store, "999--demo")
    write_running_line(intent_dir, "n5", cap: 10)

    path = subagent_transcript_path("main-sess", "agent-5")
    FileUtils.mkdir_p(File.dirname(path))
    File.open(path, "wb") do |f|
      f.puts JSON.generate("type" => "user", "message" => { "content" => packet_prompt(intent_dir, "n5") })
      f.puts JSON.generate("type" => "assistant", "message" => { "content" => [{ "type" => "tool_use", "id" => "t1" }] })
      f.write("\xFF\xFE not valid utf-8 \"type\":\"tool_use\"\n".b)
    end

    result = HookCallBudget.decide(payload(session_id: "main-sess", agent_id: "agent-5"))

    assert_nil result, "an unreadable transcript must fail open (allow), never deny"
    savepoint = File.read(File.join(intent_dir, "savepoint.md"))
    assert_includes savepoint, "CallBudget", "an unreadable transcript must leave a ledger line, not a silent gap"
    assert_includes savepoint, "main-sess"
  end

  # --- B7: the spawned hook's own overhead stays under 50ms ------------------

  def spawn_median(cmd, input, n: 5)
    times = Array.new(n) { timed_spawn(cmd, input) }
    times.sort[n / 2]
  end

  def timed_spawn(cmd, input)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    IO.popen(cmd, "r+") do |io|
      io.write(input)
      io.close_write
      io.read
    end
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000
  end

  def test_spawned_hook_overhead_under_50ms
    hook = File.expand_path("../hooks/call-budget", __dir__)
    intent_dir = File.join(@store, "999--demo")
    write_running_line(intent_dir, "n8", cap: 1000)
    write_subagent_transcript(session_id: "main-sess", agent_id: "agent-1",
                               prompt: packet_prompt(intent_dir, "n8"), tool_use_counts: [5, 5])

    capped_input = JSON.generate(payload(session_id: "main-sess", agent_id: "agent-1"))
    no_agent_input = JSON.generate(payload(session_id: "main-sess"))

    capped_median = spawn_median([hook], capped_input)
    no_agent_median = spawn_median([hook], no_agent_input)
    hook_median = [capped_median, no_agent_median].sum / 2.0
    bare_median = spawn_median(["ruby", "--disable-gems", "-e", ""], "")

    overhead = hook_median - bare_median
    assert_operator overhead, :<, 50,
                     "hook overhead #{overhead.round(1)}ms must stay under 50ms (capped median " \
                     "#{capped_median.round(1)}ms, no-agent median #{no_agent_median.round(1)}ms, " \
                     "bare ruby --disable-gems median #{bare_median.round(1)}ms)"
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
