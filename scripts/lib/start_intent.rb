# encoding: UTF-8
# frozen_string_literal: true

require_relative "bridge"
require_relative "lock"
require_relative "intent_validator"
require_relative "spec_header"
require_relative "outcome_guard"
require_relative "scaffold_intent"

# StartIntent - all logic for `scripts/start-intent` (intent 213, group 2). Boards a
# session onto an intent: arm the delivery lock, then print a read-only resume-station
# report. This is the highest-risk surface in this action set because it composes lock
# arbitration; the rule for that surface is compose the existing primitives, add nothing
# (spec D6).
#
# NEVER REIMPLEMENTS LOCK ARBITRATION. Arming is `Bridge.arm_auto` or `Bridge.arm_guided`
# and nothing else acquires anything: no new arming logic, no retry loop, no takeover path.
# This module NEVER calls the Lock module's release or takeover operations. That unguarded
# read-modify-write gap is parked intent 254's territory; start-intent reports and refuses,
# it never repairs a lock. Read-only lock inspection (`Lock.path`, `Lock.read`,
# `Lock.fresh?`, `Lock.authorized?`) is expected and used below.
#
# DETERMINISM CRITERION: every value this module prints is read from already-committed
# files or from `Bridge.arm_*`'s own return value. No model inference, no free-text
# generation.
#
# Pure and dependency-injected: never calls `exit` or `abort`, never reads `ARGV` or `ENV`
# directly. Seams: `armer:` (a lambda dispatching on mode to the two real Bridge methods),
# plus session/harness/thread values passed in as arguments rather than read from ENV here.
# Reading ENV for harness detection happens in the CLI (`scripts/start-intent`) and is
# passed down.
module StartIntent
  module_function

  EXIT_OK = 0
  EXIT_USAGE = 1
  EXIT_HELD = 3
  EXIT_UNRESOLVED = 4

  # --- Step 0: resolve inputs -------------------------------------------------------

  # `name:` for the arm call, deterministically: the intent file frontmatter's `intent:`
  # field, or the directory basename when the frontmatter is unreadable or blank. Never
  # invents a name.
  def resolve_name(intent_dir)
    fm = IntentValidator.parse_frontmatter(Bridge.intent_file(intent_dir))
    name = fm.is_a?(Hash) ? fm["intent"] : nil
    Bridge.blank?(name) ? File.basename(intent_dir) : name
  end

  # Session resolution order: explicit --session, else CLAUDE_CODE_SESSION_ID (passed in
  # as env_session, never read from ENV here), else nil. Deliberately NO fallback to the
  # lock's own recorded owner (unlike end-intent's resolve_end_session): arming as an
  # owner you cannot prove you are is wrong.
  def resolve_session(explicit, env_session)
    return explicit.to_s.strip unless Bridge.blank?(explicit)
    return env_session.to_s.strip unless Bridge.blank?(env_session)
    nil
  end

  # Harness/thread detection, mirroring skills/auto/SKILL.md's arm-the-lifecycle-gate
  # snippet exactly: a non-empty CODEX_THREAD_ID means codex (thread = that id); else a
  # non-empty CLAUDE_CODE_SESSION_ID means claude (thread = nil); else both nil. Pure:
  # takes the raw ENV strings as arguments, never reads ENV itself.
  def resolve_harness(codex_thread_id, claude_session_id)
    codex = codex_thread_id.to_s.strip
    claude = claude_session_id.to_s.strip
    return { harness: "codex", thread: codex } unless codex.empty?
    return { harness: "claude", thread: nil } unless claude.empty?
    { harness: nil, thread: nil }
  end

  # --- Step 1: pre-flight lock read (read-only, before arming) ---------------------
  #
  # Mirrors the READ-ONLY half of scripts/end-intent's preflight_lock_verdict, minus its
  # takeover branch (start-intent never takes over). Returns [verdict, lock_or_nil]:
  #   :proceed    no lock, or this session already owns/delegates it
  #   :corrupt    a lock file exists but Lock.read cannot parse it (exit 4, unconditional;
  #               unlike end-intent, freshness is never consulted for a corrupt lock,
  #               because there is no repair path here to reach for a stale one)
  #   :no_session a lock file exists and no session identity resolved from any source
  #               (exit 4)
  #   :held       a FRESH foreign lock (exit 4... exit 3, before ever calling the armer)
  #   :stale      a STALE foreign lock: fall through to arming, which arbitrates it (and
  #               raises Bridge::LockHeldError with the reclaim hint) itself
  def preflight_verdict(intent_dir, session)
    return [:proceed, nil] unless File.exist?(Lock.path(intent_dir))

    lock = Lock.read(intent_dir)
    return [:corrupt, nil] if lock.nil?
    return [:no_session, lock] if Bridge.blank?(session)
    return [:proceed, lock] if Lock.authorized?(lock, session)
    return [:held, lock] if Lock.fresh?(intent_dir)
    [:stale, lock]
  end

  def corrupt_message(intent_dir)
    "start-intent: the delivery lock at #{Lock.path(intent_dir)} exists but its content " \
      "will not parse (corrupt); refusing to arm since another session may still be " \
      "heartbeating it. Run /plastic-doctor check the lock status, or plastic-lock fix " \
      "once it is confirmed safe."
  end

  def no_session_message(intent_dir)
    "start-intent: a delivery lock exists at #{Lock.path(intent_dir)} but no session " \
      "identity could be resolved (--session or CLAUDE_CODE_SESSION_ID are both blank); " \
      "refusing rather than guessing. Pass --session explicitly."
  end

  def held_message(intent_dir, lock, harness:)
    owner = lock.is_a?(Hash) ? lock["owner_session"] : nil
    "start-intent: delivery lock for #{File.basename(intent_dir)} is held by a live " \
      "session (#{owner}); run #{Bridge.skill_ref('plastic-doctor', harness: harness)} " \
      "check the lock status"
  end

  # --- Step 2: arm -------------------------------------------------------------------

  # Default arm seam: dispatches on mode to the two real Bridge methods. Nothing else
  # acquires anything.
  def default_armer
    lambda do |mode, session:, intent_id:, intent_dir:, store:, name:, harness:, agent:,
               model:, thread:|
      case mode
      when "auto"
        Bridge.arm_auto(session, intent_id: intent_id, intent_dir: intent_dir, store: store,
                        name: name, harness: harness, agent: agent, model: model, thread: thread)
      when "guided"
        Bridge.arm_guided(session, intent_id: intent_id, intent_dir: intent_dir, store: store,
                          name: name, harness: harness, agent: agent, model: model, thread: thread)
      end
    end
  end

  # --- Step 3: the resume-station report (read-only, after arming) -----------------

  # Count-only helper for the printed "actions/: <n> real action file(s)" line. The
  # STATION gate (whether How is delivered) is decided exclusively by
  # Bridge.has_real_action?, called separately in build_report; this exists only to render
  # a number and must never be used for any pass/fail decision.
  def real_action_count(intent_dir)
    Dir.glob("#{intent_dir}/actions/*.md").count do |f|
      File.file?(f) && File.size(f) > 0 && Bridge.stage_file_present?(f)
    end
  rescue StandardError
    0
  end

  # Classify outcome.md into one of three states, per the spec's outcome.md nuance:
  # `scaffold-intent outcome` writes a real (non-sentinel) outcome.md while leaving the
  # frontmatter disposition at the template placeholder `delivered|abandoned`, so a naive
  # sentinel check would misreport that as Done. Returns [state, reason]:
  #   "not_started" the sentinel is still present (or the file is absent), reason nil
  #   "authored"    sentinel gone AND OutcomeGuard.reason(intent_dir, "delivered") is nil
  #   "scaffolded"  sentinel gone AND OutcomeGuard.reason(...) returns a reason string
  # OutcomeGuard.reason is the single existing definition of "is outcome.md real for this
  # close"; this never re-derives that definition.
  def classify_outcome(intent_dir)
    outcome_path = File.join(intent_dir, "outcome.md")
    return ["not_started", nil] unless Bridge.stage_file_present?(outcome_path)

    reason = OutcomeGuard.reason(intent_dir, "delivered")
    reason.nil? ? ["authored", nil] : ["scaffolded", reason]
  end

  def settled_text(header)
    return "no" unless header[:settled]
    header[:settled_reason] ? "yes (#{header[:settled_reason]})" : "yes"
  end

  # Build the resume-station report. Every value comes from already-committed files
  # (Bridge.stage_file_present?, Bridge.has_real_action?, SpecHeader, OutcomeGuard) or from
  # `data`, the Hash Bridge.arm_* itself returned. No model inference, no free text beyond
  # the fixed shape below.
  def build_report(intent_dir:, mode:, data:)
    spec_path = File.join(intent_dir, "spec.md")
    plan_path = File.join(intent_dir, "plan.md")
    checklist_path = File.join(intent_dir, "checklist.md")

    spec_delivered = Bridge.stage_file_present?(spec_path)
    plan_delivered = Bridge.stage_file_present?(plan_path)
    checklist_delivered = Bridge.stage_file_present?(checklist_path)
    has_action = Bridge.has_real_action?(intent_dir)
    how_triple = plan_delivered && checklist_delivered && has_action

    outcome_state, outcome_reason = classify_outcome(intent_dir)

    resume_at =
      if !spec_delivered
        "Why"
      elsif !how_triple
        "How"
      elsif outcome_state != "authored"
        "Exec"
      else
        "Done"
      end

    header = SpecHeader.parse_file(spec_path)
    tier = header[:tier] || "unknown"

    worktree_code = data.dig("worktree", "code")
    worktree_line = Bridge.blank?(worktree_code) ? "not provisioned" : worktree_code

    outcome_line =
      case outcome_state
      when "authored" then "authored"
      when "scaffolded" then "scaffolded, not authored (#{outcome_reason})"
      else "not started"
      end

    lines = []
    lines << "start-intent: #{File.basename(intent_dir)}"
    lines << "  mode:        #{mode}"
    lines << "  session:     #{data['session']}"
    lines << "  lock:        held by #{data.dig('lock', 'owner_session')} (ours)"
    lines << "  worktree:    #{worktree_line}"
    lines << "  tier:        #{tier}"
    lines << "  settled:     #{settled_text(header)}"
    lines << "  spec.md:     #{spec_delivered ? 'delivered' : 'not started'}"
    lines << "  plan.md:     #{plan_delivered ? 'delivered' : 'not started'}"
    lines << "  checklist.md: #{checklist_delivered ? 'delivered' : 'not started'}"
    lines << "  actions/:    #{real_action_count(intent_dir)} real action file(s)"
    lines << "  outcome.md:  #{outcome_line}"
    lines << "  resume at:   #{resume_at}"
    lines.join("\n")
  end

  # --- entry point --------------------------------------------------------------------

  def usage_result(message)
    { exit_code: EXIT_USAGE, stderr: [message], stdout: [] }
  end

  def deny_result(code, message)
    { exit_code: code, stderr: [message], stdout: [] }
  end

  def run(store:, id:, mode:, session:, env_session:, harness:, thread:, armer: default_armer)
    return usage_result("--store is required") if Bridge.blank?(store)
    return usage_result("--id is required") if Bridge.blank?(id)
    return usage_result("--mode is required") if Bridge.blank?(mode)
    unless %w[auto guided].include?(mode)
      return usage_result("--mode must be one of auto, guided (got #{mode.inspect})")
    end

    store_abs = ScaffoldIntent.expand(store)
    return usage_result("store dir does not exist: #{store_abs}") unless Dir.exist?(store_abs)

    intent_dir, resolve_err = ScaffoldIntent.resolve_intent_dir(store_abs, id)
    return usage_result(resolve_err) if intent_dir.nil?

    name = resolve_name(intent_dir)
    key_session = resolve_session(session, env_session)

    verdict, lock = preflight_verdict(intent_dir, key_session)
    case verdict
    when :corrupt
      return deny_result(EXIT_UNRESOLVED, corrupt_message(intent_dir))
    when :no_session
      return deny_result(EXIT_UNRESOLVED, no_session_message(intent_dir))
    when :held
      return deny_result(EXIT_HELD, held_message(intent_dir, lock, harness: harness))
    end
    # :proceed and :stale both fall through to arming; Bridge.arm_* arbitrates :stale
    # itself (and raises Bridge::LockHeldError with the reclaim hint) via its own
    # up-to-date Lock.acquire call.

    data =
      begin
        armer.call(mode, session: key_session, intent_id: id, intent_dir: intent_dir,
                   store: store_abs, name: name, harness: harness, agent: nil, model: nil,
                   thread: thread)
      rescue Bridge::LockHeldError => e
        return deny_result(EXIT_HELD, e.message)
      end

    report = build_report(intent_dir: intent_dir, mode: mode, data: data)
    { exit_code: EXIT_OK, stderr: [], stdout: [report] }
  end
end
