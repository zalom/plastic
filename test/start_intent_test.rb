# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require_relative "../scripts/lib/start_intent"
require_relative "../scripts/lib/bridge"
require_relative "../scripts/lib/lock"

# start-intent (intent 213, group 2): arms the delivery lock (via Bridge's real arm
# seam only) then prints a read-only resume-station report. Hermetic:
# every fixture lives under Dir.mktmpdir, logic tests use the injected `armer:` seam so no
# real arm ever runs, and the one end-to-end subprocess test isolates its env exactly as
# test/end_intent_test.rb:44-49 does. No test in this file acquires a real lock or arms a
# real bridge.
class StartIntentTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/start-intent", __dir__)
  SENTINEL = Bridge::PLACEHOLDER_SENTINEL

  def setup
    @home = Dir.mktmpdir("start-intent-home")
    @store = File.join(@home, "store")
    FileUtils.mkdir_p(@store)
    @tmp_bridge = Dir.mktmpdir("start-intent-bridge")
  end

  def teardown
    FileUtils.rm_rf(@home)
    FileUtils.rm_rf(@tmp_bridge)
  end

  # --- fixture builders --------------------------------------------------------------

  def build_intent_dir(id: "213", slug: "demo", name: "Demo intent")
    dir = File.join(@store, "#{id}--#{slug}")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "#{id}--#{slug}.md"), <<~MD)
      ---
      id: "#{id}"
      intent: "#{name}"
      sources: []
      chain: []
      created: 2026-07-01
      author: human
      tags: []
      ---

      ## Intent
      #{name}

      ## Context

      ### Decisions
      - a decision

      ## Outcome
      (the result)

      ## Insights

      ## Links
      <!-- No sources or chain; this intent has no graph edges to project. -->
    MD
    dir
  end

  def write_sentinel(path)
    File.write(path, "#{SENTINEL}\n")
  end

  def write_spec(dir, tier: "L", settled_reason: nil)
    header = +""
    header << "Tier: #{tier}\n" if tier
    header << "Settled: yes (#{settled_reason})\n" if settled_reason
    File.write(File.join(dir, "spec.md"), <<~MD)
      #{header}
      # Spec: Demo

      ## Acceptance Criteria
      - [ ] one
    MD
  end

  def write_plan(dir)
    File.write(File.join(dir, "plan.md"), "# Plan\n\nreal plan content\n")
  end

  def write_checklist(dir)
    File.write(File.join(dir, "checklist.md"), "# Checklist\n\n- [ ] one\n")
  end

  def write_real_action(dir)
    FileUtils.mkdir_p(File.join(dir, "actions"))
    File.write(File.join(dir, "actions", "ACTION_1.md"), "# ACTION_1\n\nreal content\n")
  end

  def write_gitkeep_only_actions(dir)
    FileUtils.mkdir_p(File.join(dir, "actions"))
    File.write(File.join(dir, "actions", ".gitkeep"), "")
  end

  def write_outcome_scaffolded(dir)
    File.write(File.join(dir, "outcome.md"), <<~MD)
      ---
      disposition: delivered|abandoned
      ---

      # Outcome: Demo

      ## Verification
      stub
    MD
  end

  def write_outcome_authored(dir)
    File.write(File.join(dir, "outcome.md"), <<~MD)
      ---
      disposition: delivered
      ---

      # Outcome: Demo

      ## Verification
      real verification content
    MD
  end

  def write_outcome_authored_abandoned(dir)
    File.write(File.join(dir, "outcome.md"), <<~MD)
      ---
      disposition: abandoned
      ---

      # Outcome: Demo

      ## Verification
      real verification content, disposition abandoned
    MD
  end

  def write_fresh_lock(dir, owner: "other-session")
    payload = Lock.payload(session: owner, type: "delivery", host: "h", now: Time.now)
    File.write(Lock.path(dir), JSON.pretty_generate(payload))
  end

  def write_corrupt_lock(dir)
    File.write(Lock.path(dir), "not json{{{")
  end

  def fake_armer(recorded, result: nil)
    lambda do |mode, **kwargs|
      recorded << { mode: mode }.merge(kwargs)
      result || { "session" => kwargs[:session],
                  "lock" => { "owner_session" => kwargs[:session] },
                  "worktree" => { "code" => nil } }
    end
  end

  def base_data(session: "s1")
    { "session" => session, "lock" => { "owner_session" => session }, "worktree" => { "code" => nil } }
  end

  # Isolates the child's environment (no ambient CLAUDE_CODE_SESSION_ID, a dedicated
  # PLASTIC_TMP), exactly as test/end_intent_test.rb:44-49 does.
  def run_start_intent(*args)
    env = { "CLAUDE_CODE_SESSION_ID" => nil, "PLASTIC_TMP" => @tmp_bridge }
    out = IO.popen(env, [RbConfig.ruby, SCRIPT, *args], err: [:child, :out], &:read)
    [out.strip, $?.exitstatus]
  end

  # --- 1: mode routes to the correct branch of the seam, full kwargs -----------------

  def test_mode_auto_routes_with_full_kwargs
    dir = build_intent_dir
    recorded = []
    result = StartIntent.run(store: @store, id: "213", mode: "auto", session: "s1",
                              env_session: nil, harness: nil, thread: nil,
                              armer: fake_armer(recorded))
    assert_equal 0, result[:exit_code]
    assert_equal 1, recorded.length
    call = recorded.first
    assert_equal "auto", call[:mode]
    assert_equal "213", call[:intent_id]
    assert_equal dir, call[:intent_dir]
    assert_equal @store, call[:store]
    assert_equal "Demo intent", call[:name]
  end

  def test_mode_guided_routes_with_full_kwargs
    build_intent_dir
    recorded = []
    result = StartIntent.run(store: @store, id: "213", mode: "guided", session: "s1",
                              env_session: nil, harness: nil, thread: nil,
                              armer: fake_armer(recorded))
    assert_equal 0, result[:exit_code]
    assert_equal "guided", recorded.first[:mode]
  end

  # --- 2: name from frontmatter, fallback to dir basename -----------------------------

  def test_name_resolves_from_frontmatter_intent_field
    dir = build_intent_dir(name: "Custom Name")
    assert_equal "Custom Name", StartIntent.resolve_name(dir)
  end

  def test_name_falls_back_to_dir_basename_when_frontmatter_unreadable
    dir = File.join(@store, "213--nofile")
    FileUtils.mkdir_p(dir)
    assert_equal "213--nofile", StartIntent.resolve_name(dir)
  end

  # --- 3: station classification, one row per test ------------------------------------

  def test_station_why_when_spec_is_sentinel_only
    dir = build_intent_dir
    write_sentinel(File.join(dir, "spec.md"))
    report = StartIntent.build_report(intent_dir: dir, mode: "auto", data: base_data)
    assert_match(/resume at:\s+Why/, report)
  end

  def test_station_how_when_only_spec_is_real
    dir = build_intent_dir
    write_spec(dir)
    report = StartIntent.build_report(intent_dir: dir, mode: "auto", data: base_data)
    assert_match(/resume at:\s+How/, report)
  end

  def test_station_exec_when_the_how_triple_is_real
    dir = build_intent_dir
    write_spec(dir)
    write_plan(dir)
    write_checklist(dir)
    write_real_action(dir)
    report = StartIntent.build_report(intent_dir: dir, mode: "auto", data: base_data)
    assert_match(/resume at:\s+Exec/, report)
  end

  def test_gitkeep_only_actions_does_not_reach_exec
    dir = build_intent_dir
    write_spec(dir)
    write_plan(dir)
    write_checklist(dir)
    write_gitkeep_only_actions(dir)
    report = StartIntent.build_report(intent_dir: dir, mode: "auto", data: base_data)
    refute_match(/resume at:\s+Exec/, report)
    assert_match(/resume at:\s+How/, report)
  end

  def test_station_done_when_outcome_is_authored
    dir = build_intent_dir
    write_spec(dir)
    write_plan(dir)
    write_checklist(dir)
    write_real_action(dir)
    write_outcome_authored(dir)
    report = StartIntent.build_report(intent_dir: dir, mode: "auto", data: base_data)
    assert_match(/resume at:\s+Done/, report)
    assert_match(/outcome\.md:\s+authored/, report)
  end

  # --- 3b: BLOCKING 3 regression: a fully-authored ABANDONED outcome.md must classify
  # as authored too, not get hardcoded-delivered-misread as scaffolded and pointed back
  # into Exec ---------------------------------------------------------------------------

  def test_station_done_when_outcome_is_authored_abandoned
    dir = build_intent_dir
    write_spec(dir)
    write_plan(dir)
    write_checklist(dir)
    write_real_action(dir)
    write_outcome_authored_abandoned(dir)
    report = StartIntent.build_report(intent_dir: dir, mode: "auto", data: base_data)
    assert_match(/resume at:\s+Done/, report)
    assert_match(/outcome\.md:\s+authored/, report)
  end

  # --- 4: scaffolded-but-unauthored outcome.md never reads as Done --------------------

  def test_scaffolded_outcome_reports_not_authored_and_stays_at_exec
    dir = build_intent_dir
    write_spec(dir)
    write_plan(dir)
    write_checklist(dir)
    write_real_action(dir)
    write_outcome_scaffolded(dir)
    report = StartIntent.build_report(intent_dir: dir, mode: "auto", data: base_data)
    assert_match(/outcome\.md:\s+scaffolded, not authored/, report)
    assert_match(/resume at:\s+Exec/, report)
    refute_match(/resume at:\s+Done/, report)
  end

  # --- 5: tier and settled lines from SpecHeader --------------------------------------

  def test_tier_and_settled_lines_from_spec_header
    dir = build_intent_dir
    write_spec(dir, tier: "M", settled_reason: "design fixed")
    report = StartIntent.build_report(intent_dir: dir, mode: "auto", data: base_data)
    assert_match(/tier:\s+M/, report)
    assert_match(/settled:\s+yes \(design fixed\)/, report)
  end

  def test_absent_settled_line_prints_settled_no
    dir = build_intent_dir
    write_spec(dir, tier: "S", settled_reason: nil)
    report = StartIntent.build_report(intent_dir: dir, mode: "auto", data: base_data)
    assert_match(/settled:\s+no/, report)
  end

  # --- 6: exit 3 on a fresh foreign lock; armer never called --------------------------

  def test_exit_3_when_fresh_foreign_lock_present
    dir = build_intent_dir
    write_fresh_lock(dir, owner: "other-session")
    recorded = []
    result = StartIntent.run(store: @store, id: "213", mode: "auto", session: "me",
                              env_session: nil, harness: nil, thread: nil,
                              armer: fake_armer(recorded))
    assert_equal 3, result[:exit_code]
    assert_empty recorded
    assert_match(/other-session/, result[:stderr].join)
  end

  # --- 7: exit 4 on an unparseable lock ------------------------------------------------

  def test_exit_4_when_lock_file_will_not_parse
    dir = build_intent_dir
    write_corrupt_lock(dir)
    recorded = []
    result = StartIntent.run(store: @store, id: "213", mode: "auto", session: "me",
                              env_session: nil, harness: nil, thread: nil,
                              armer: fake_armer(recorded))
    assert_equal 4, result[:exit_code]
    assert_empty recorded
  end

  # --- 8: exit 4 when no session identity resolves at all -----------------------------

  def test_exit_4_when_lock_present_and_no_session_identity_resolves
    dir = build_intent_dir
    write_fresh_lock(dir, owner: "other-session")
    recorded = []
    result = StartIntent.run(store: @store, id: "213", mode: "auto", session: nil,
                              env_session: nil, harness: nil, thread: nil,
                              armer: fake_armer(recorded))
    assert_equal 4, result[:exit_code]
    assert_empty recorded
  end

  # --- 9: exit 3 when the armer seam raises LockHeldError ------------------------------

  def test_exit_3_when_armer_seam_raises_lock_held_error
    build_intent_dir
    raising_armer = lambda do |_mode, **_kwargs|
      raise Bridge::LockHeldError, "delivery lock is stale; reclaim via doctor"
    end
    result = StartIntent.run(store: @store, id: "213", mode: "auto", session: "me",
                              env_session: nil, harness: nil, thread: nil,
                              armer: raising_armer)
    assert_equal 3, result[:exit_code]
    assert_match(/delivery lock is stale; reclaim via doctor/, result[:stderr].join)
  end

  # --- 10: exit 1 for every usage failure ----------------------------------------------

  def test_exit_1_for_usage_and_resolution_failures
    build_intent_dir
    recorded = []
    armer = fake_armer(recorded)

    missing_store = StartIntent.run(store: nil, id: "213", mode: "auto", session: "s",
                                     env_session: nil, harness: nil, thread: nil, armer: armer)
    assert_equal 1, missing_store[:exit_code]

    missing_id = StartIntent.run(store: @store, id: nil, mode: "auto", session: "s",
                                  env_session: nil, harness: nil, thread: nil, armer: armer)
    assert_equal 1, missing_id[:exit_code]

    missing_mode = StartIntent.run(store: @store, id: "213", mode: nil, session: "s",
                                    env_session: nil, harness: nil, thread: nil, armer: armer)
    assert_equal 1, missing_mode[:exit_code]

    bad_mode = StartIntent.run(store: @store, id: "213", mode: "fast", session: "s",
                                env_session: nil, harness: nil, thread: nil, armer: armer)
    assert_equal 1, bad_mode[:exit_code]

    no_match = StartIntent.run(store: @store, id: "999", mode: "auto", session: "s",
                                env_session: nil, harness: nil, thread: nil, armer: armer)
    assert_equal 1, no_match[:exit_code]

    FileUtils.mkdir_p(File.join(@store, "213--dup2"))
    ambiguous = StartIntent.run(store: @store, id: "213", mode: "auto", session: "s",
                                 env_session: nil, harness: nil, thread: nil, armer: armer)
    assert_equal 1, ambiguous[:exit_code]

    assert_empty recorded
  end

  def test_unknown_flag_exits_1_via_the_real_subprocess
    out, status = run_start_intent("--bogus")
    assert_equal 1, status
    assert_match(/unknown argument/, out)
  end

  # --- 10b: BLOCKING 6 regression: the default_armer seam (never exercised by any test
  # before this) routes each mode to the correct real Bridge method. Intercepts exactly
  # at the Bridge class-method boundary so nothing real is ever armed: no lock file, no
  # worktree provisioning, no ambient session. Uses tmpdir fixtures (@store, from setup)
  # and synthesized session/thread ids, never CLAUDE_CODE_SESSION_ID. -------------------

  # Replaces Bridge's real `method_name` with a double that records every call and
  # returns a fixture Hash, never running the real Bridge.arm (no lock, no worktree, no
  # ambient session touched). Restores the original method afterward even if the block
  # raises.
  def stub_bridge_arm(method_name, calls)
    original = Bridge.method(method_name)
    Bridge.define_singleton_method(method_name) do |session, **kwargs|
      calls << { session: session, kwargs: kwargs }
      { "session" => "fake-armed", "lock" => { "owner_session" => "fake-armed" },
        "worktree" => { "code" => nil } }
    end
    yield
  ensure
    Bridge.define_singleton_method(method_name, original)
  end

  def test_default_armer_routes_auto_mode_to_bridge_arm_auto
    calls = []
    stub_bridge_arm(:arm_auto, calls) do
      result = StartIntent.default_armer.call(
        "auto", session: "synth-session-auto", intent_id: "213", intent_dir: @store,
        store: @store, name: "Demo intent", harness: "claude", agent: nil, model: nil,
        thread: "synth-thread-#{Process.pid}"
      )
      assert_equal 1, calls.length
      assert_equal "synth-session-auto", calls.first[:session]
      assert_equal "213", calls.first[:kwargs][:intent_id]
      assert_equal "fake-armed", result["session"]
    end
  end

  def test_default_armer_routes_guided_mode_to_bridge_arm_guided
    calls = []
    stub_bridge_arm(:arm_guided, calls) do
      result = StartIntent.default_armer.call(
        "guided", session: "synth-session-guided", intent_id: "213", intent_dir: @store,
        store: @store, name: "Demo intent", harness: "claude", agent: nil, model: nil,
        thread: "synth-thread-#{Process.pid}"
      )
      assert_equal 1, calls.length
      assert_equal "synth-session-guided", calls.first[:session]
      assert_equal "fake-armed", result["session"]
    end
  end

  def test_default_armer_never_crosses_modes
    auto_calls = []
    guided_calls = []
    stub_bridge_arm(:arm_auto, auto_calls) do
      stub_bridge_arm(:arm_guided, guided_calls) do
        StartIntent.default_armer.call(
          "auto", session: "synth-session-cross", intent_id: "213", intent_dir: @store,
          store: @store, name: "Demo intent", harness: nil, agent: nil, model: nil,
          thread: nil
        )
      end
    end
    assert_equal 1, auto_calls.length
    assert_empty guided_calls
  end

  # --- 11: guard: never Lock.release, never Lock.takeover ------------------------------

  def test_never_calls_lock_release_or_lock_takeover
    lib_src = File.read(File.expand_path("../scripts/lib/start_intent.rb", __dir__))
    cli_src = File.read(File.expand_path("../scripts/start-intent", __dir__))
    combined = lib_src + cli_src
    refute_match(/Lock\.release\b/, combined,
                 "start-intent must never call Lock.release; intent 254 owns that gap, " \
                 "start-intent reports and refuses, it never repairs a lock")
    refute_match(/Lock\.takeover\b/, combined,
                 "start-intent must never call Lock.takeover; intent 254 owns that gap, " \
                 "start-intent reports and refuses, it never repairs a lock")
  end
end
