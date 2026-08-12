# encoding: UTF-8
# frozen_string_literal: true

# CodexEditGates (intent 251): the merged Codex apply_patch edit path. One
# process, one stdin parse, one envelope parse, five gates in-process.
#
# Before this, ~/.codex/hooks.json registered five separate PreToolUse commands
# on the apply_patch matcher and three of them spawned a further run_core child
# per file operation: eight processes per edit, ten across a full edit cycle.
# This is the Codex mirror of what intent 244 did for Claude (spec D-e of that
# intent parked it as a successor).
#
# Every DECISION here comes from scripts/lib/edit_gates.rb, the same functions
# scripts/hook-edit-gates drives for Claude. This file contributes exactly three
# Codex-specific things and nothing else:
#   1. the per-operation Context (the patch envelope carries a path plus ADDED
#      lines, not Claude's file_path plus content pair),
#   2. the add-only rule for create-gate (Update/Delete/Move defer to the
#      PostToolUse gate-check backstop, intent 102 spec Decision 5), and
#   3. the two-pass evaluation that keeps savepoint-pre's ledger append
#      unconditional across a multi-operation patch (intent 244 spec D-c).
#
# NO SUBPROCESS MAY EVER BE ADDED TO THIS FILE. That is the whole point of the
# intent, and test/codex_edit_gates_test.rb asserts it against this source.
require "stringio"
require_relative "edit_gates"
require_relative "hook_registry"

module CodexEditGates
  module_function

  # Pass 1 and pass 2 of the two-pass evaluation (spec D3). Both slices preserve
  # HookRegistry::CODEX_GATE_TOOLS key order, which is Claude's evaluation order
  # (spec D5): savepoint-pre, lock-gate, code-gate, links-gate, create-gate.
  SAVEPOINT_TOOLS = HookRegistry::CODEX_GATE_TOOLS.select { |gate, _| gate == "savepoint-pre" }.freeze
  DENY_TOOLS      = HookRegistry::CODEX_GATE_TOOLS.reject { |gate, _| gate == "savepoint-pre" }.freeze

  # One Context per file operation. gate_path and file_path both carry the
  # envelope's raw path, exactly as the five popened cores received it in ARGV[0]
  # before the merge. content is always a String (never nil), because
  # ApplyPatchEnvelope gives a Delete op a nil added_content and today's
  # dispatcher already called .to_s on it at every call site. harness is "codex"
  # so lock-gate and the claim gate render deny reasons in the $plastic-<name>
  # form (intent 201 D2).
  def context_for(payload, op, env: ENV)
    session = payload["session_id"]
    session = env["CLAUDE_CODE_SESSION_ID"] if session.to_s.empty?

    EditGates::Context.new(
      tool_name: payload["tool_name"],
      session: (session unless session.to_s.empty?),
      gate_path: op.path,
      file_path: op.path,
      savepoint_path: op.path,
      content: op.added_content.to_s,
      harness: "codex",
    )
  end

  # create-gate is a pre-write veto for ADD operations only (spec D2).
  # EditGates.create_gate has no such rule: fed a partial Update hunk as content
  # it would run IntentValidator on a fragment and FALSE-DENY a legitimate write.
  def create_gate(ctx, op)
    return EditGates::ALLOW unless op.op == :add
    EditGates.create_gate(ctx)
  end

  def route_for(op)
    lambda do |gate, ctx|
      case gate
      when "savepoint-pre" then EditGates.savepoint_pre(ctx)
      when "lock-gate"     then EditGates.lock_gate(ctx)
      when "code-gate"     then EditGates.code_gate(ctx)
      when "links-gate"    then EditGates.links_gate(ctx)
      when "create-gate"   then create_gate(ctx, op)
      end
    end
  end

  # True iff tool_name is a NON-EMPTY string that no CODEX_GATE_TOOLS entry
  # matches. An empty/missing tool_name already means "the harness matched but
  # did not name the tool" and every gate runs (EditGates.tool_applies?'s own
  # empty-name rule); this is the OTHER unmatched case, a non-empty tool_name
  # this dispatcher does not recognize. Checked once against "apply_patch",
  # since every CODEX_GATE_TOOLS value is the identical single-entry list.
  def unexpected_tool_name?(tool_name)
    return false if tool_name.to_s.empty?
    !EditGates.tool_applies?(tool_name, %w[apply_patch])
  end

  # Returns the process exit code. Two passes (spec D3):
  #   pass 1 runs savepoint-pre over EVERY op. It never denies, and running it
  #   before any deny check keeps its started ledger append unconditional, so
  #   op B's ledger line still lands when op A is blocked.
  #   pass 2 runs the four denying gates per op, first deny wins.
  # EditGates.dispatch returns 0 both for "allowed" and for lock-gate's JSON
  # deny, so pass 2 captures stdout per op: a non-empty buffer IS a deny, and it
  # is printed and evaluation stops. Without that capture a second op could emit
  # a second deny JSON.
  #
  # Codex only ever invokes this dispatcher from the apply_patch matcher, so by
  # the time we get here the harness HAS already matched, regardless of what
  # tool_name the payload itself carries. A non-empty, unrecognized tool_name
  # (a future Codex rename, or a malformed/adversarial payload) must therefore
  # never silently skip every gate: that is the coverage WEAKENING
  # EditGates.tool_applies?'s own empty-name rule exists to prevent, just
  # triggered from the opposite direction (an unrecognized name here, not a
  # missing one there). Loud and safe: warn once to err and run all five gates
  # exactly as if tool_name had been "apply_patch", rather than silent and
  # permissive.
  def dispatch(ops:, payload:, out: $stdout, err: $stderr)
    if unexpected_tool_name?(payload["tool_name"])
      err.puts "plastic codex edit-gates: unexpected tool_name #{payload["tool_name"].inspect}; " \
                "the apply_patch matcher already selected this dispatcher, so all five gates run anyway"
      payload = payload.merge("tool_name" => "apply_patch")
    end

    pairs = ops.map { |op| [op, context_for(payload, op)] }

    pairs.each do |op, ctx|
      EditGates.dispatch(ctx: ctx, route: route_for(op), gate_tools: SAVEPOINT_TOOLS,
                         out: StringIO.new, err: err)
    end

    pairs.each do |op, ctx|
      buffer = StringIO.new
      code = EditGates.dispatch(ctx: ctx, route: route_for(op), gate_tools: DENY_TOOLS,
                                out: buffer, err: err)
      return code unless code.zero?
      next if buffer.string.empty?

      out.print buffer.string
      return 0
    end

    0
  end
end
