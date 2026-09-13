# encoding: UTF-8
# frozen_string_literal: true

require "yaml"
require "date"
require "time"
require "open3"
require "fileutils"
require_relative "node_return"
require_relative "node_ledger"
require_relative "node_worktree"
require_relative "node_file"
require_relative "node_input"
require_relative "ready_set"
require_relative "core_integrity"
require_relative "runner_core"
require_relative "worktree"
require_relative "insights"
require_relative "savepoint"
require_relative "guarded_append"
require_relative "atomic_write"
require_relative "runner_proposals"

# RunnerAbsorb (intent 340, G7, n4): the gate that turns one executor return
# into exactly one node ledger transition. It runs six checks in a fixed
# order - integrity, schema, scope, named_tests, merge, suite - and stops at
# the first refusal. Only a clean pass through all six writes `done`; every
# other path writes `failed_verification`, `needs_decision` or `blocked`,
# carrying the reason the gate stopped at and `gates=`, the checks that
# actually ran.
#
# `done` is written only on code-verified evidence: the runner re-derives
# the merge commit and the suite result itself, never trusting the
# executor's own report of either. The return's `commit:` field is a
# required attestation at the schema layer (row 4.6), not the value that
# lands on the ledger line - the merge's own commit wins whenever a merge
# actually ran (a work node); the return's commit is the fallback only when
# no merge exists to measure (a verify or research node's kind, out of this
# node's tested scope).
#
# Pure and dependency-injected down to the clock: every side effect -
# core integrity, the worktree module, git itself, the suite command, the
# project's verify reader - is an injectable keyword argument with a real
# default, so a test never touches a real repository, a real suite, or a
# real filesystem outside its own tmpdir.
module RunnerAbsorb
  module_function

  CHECKS = %w[integrity schema scope named_tests merge suite].freeze

  # M1: `default_project_reader`'s own sentinel for "the project record
  # exists but could not be parsed" - distinct from nil ("no verify command
  # declared at all, or no project record"), so absorb can block rather than
  # silently proceeding as if nothing were declared.
  UNREADABLE_VERIFY_COMMAND = :verify_command_unreadable

  # The one joined-line cap for a node's findings on one return (D16): a
  # nested structure never reaches this far (NodeReturn already coerced it
  # to plain strings), this cap is purely about line length.
  FINDING_CAP = 200

  PROJECT_LAYOUT_RE = %r{\A(.*)/projects/([^/]+)/store/[^/]+\z}.freeze

  # absorb(context, node:, return_path:) -> a result hash describing the one
  # transition it wrote (or attempted to write). Never raises across its own
  # boundary except GuardedAppend::Unavailable's own explicit recovery path
  # (row 4.40), which is caught, not propagated.
  def absorb(context, node:, return_path:, now: Time.now, allow_core_drift: false,
             integrity_checker: CoreIntegrity.method(:check),
             worktree: NodeWorktree,
             ledger: NodeLedger,
             runner: Worktree::ShellRunner.new,
             suite_runner: method(:default_suite_runner),
             project_reader: method(:default_project_reader),
             proposals: RunnerProposals)
    node = node.to_s
    intent_dir = context.intent_dir
    savepoint_path = File.join(intent_dir.to_s, "savepoint.md")
    content = File.exist?(savepoint_path) ? File.read(savepoint_path) : ""
    entries = NodeLedger.entries_from_content(content)

    # Row 4.30: a return for a node that is not currently `running` (already
    # terminal, reclaimed, or never dispatched) is refused outright, nothing
    # is written.
    current_state = NodeLedger.status_for_content(content, node)
    return refused("node_not_running") unless current_state == "running"

    holder = holder_for(entries, node)
    # 340b n8: the harness that ran this attempt, read off the node's own
    # `running` line - never the harness of the session doing the absorbing
    # (row 8.12). `extra_fields` carries it into every terminal fields hash
    # below through the same `.merge(extra_fields)` every path already uses,
    # so it reaches `done`, every `failed_verification`/`needs_decision`, and
    # `blocked` alike; a running line with no `harness=` leaves it out of
    # `extra_fields` entirely, so nothing invents a value (row 8.13).
    harness = harness_for(entries, node)
    extra_fields = {}
    extra_fields[:harness] = harness if harness

    node_decl = ((context.graph || {})[:nodes] || {})[node] || {}
    kind = node_decl[:kind]
    declared_files = normalize_files(node_decl[:files])

    # v2 NEW-2: a `graph.md` that failed to parse, or a node whose kind
    # cannot be resolved from it, refuses right here - before ANY check
    # runs. Falling through with `kind` nil used to skip the whole work-node
    # branch (no merge ever ran), pass scope vacuously (`declared_files` was
    # empty), and land `done` carrying the executor's own self-reported
    # commit on work nothing had verified ever reached the intent branch.
    unless (context.graph || {})[:ok] && !kind.nil?
      fields = { reason: "invalid_graph", holder: holder }.merge(extra_fields)
      return write_transition(savepoint_path, context, node, "blocked", fields, now: now, ledger: ledger)
    end

    checks_ran = []

    # 1. integrity ------------------------------------------------------------
    checks_ran << "integrity"
    integrity = integrity_checker.call(plastic_home: context.plastic_home)
    unless integrity[:ok]
      if allow_core_drift
        extra_fields["allow_core_drift"] = "true"
      else
        fields = { reason: "core_integrity", core_drift: drift_summary(integrity), holder: holder,
                   gates: checks_ran.join("+") }.merge(extra_fields)
        return write_transition(savepoint_path, context, node, "blocked", fields, now: now, ledger: ledger)
      end
    end

    # 2. schema -----------------------------------------------------------------
    checks_ran << "schema"
    text = read_return_text(return_path)
    parsed = NodeReturn.parse(text)

    attempt = NodeInput.compute_attempt_number(intent_dir: intent_dir, node: node, lease_flag_given: false,
                                                 entries: entries)
    preserve_return_file(intent_dir, node, attempt, return_path, text)

    unless parsed.ok
      return fail_check(savepoint_path, context, node, "return_unparsable", checks_ran, holder, extra_fields, now, ledger)
    end
    if parsed.node != node
      return fail_check(savepoint_path, context, node, "node_mismatch", checks_ran, holder, extra_fields, now, ledger)
    end

    append_findings(intent_dir, node, parsed.findings, now: now)

    proposal_result = nil
    finish = ->(result) { result.merge(proposal: proposal_result) }

    # B1: the return's own status governs from here on. The six mechanical
    # checks (3-6) exist to VERIFY a `done` claim, never to overrule an
    # executor's own report of its failure or its own open question - a
    # `needs_decision`, `blocked` or `failed_verification` return writes
    # exactly that state, carrying the field its own schema required
    # (`question` or `reason`), and stops here. Only `done` falls through.
    #
    # v2 NEW-1: the prose riding in `question`/`reason` is the executor's
    # own free text - a YAML block scalar (a two-line question) is the
    # natural way to write it, and `NodeLedger.normalize_value` refuses a
    # tab or a newline outright. Squashed to one line before it ever reaches
    # the ledger, same as every other whitespace run the ledger's own format
    # already collapses.
    unless parsed.status == "done"
      fields = { holder: holder, gates: checks_ran.join("+") }.merge(extra_fields)
      fields[:question] = squash_prose(parsed.question) if parsed.status == "needs_decision"
      fields[:reason] = squash_prose(parsed.reason) if %w[blocked failed_verification].include?(parsed.status)
      return finish.call(write_transition(savepoint_path, context, node, parsed.status, fields, now: now, ledger: ledger))
    end

    # 340 n10/n11, M4/row 11.14: a proposal is accepted or refused only on a
    # `done` return, right after the schema gate - the only production
    # caller RunnerProposals ever gets. An executor looping on retries must
    # never grow the graph on a failing attempt (v2 minor 11). Every `done`
    # return from here on carries `proposal:` (nil when it proposed
    # nothing), so a refusal is surfaced in the step report rather than left
    # to a savepoint comment nobody reads (row 10.3).
    if Array(parsed.proposed_nodes).any? || Array(parsed.proposed_edges).any?
      proposal_result = proposals.accept(context, proposer: node, proposed_nodes: parsed.proposed_nodes,
                                          proposed_edges: parsed.proposed_edges, now: now)
      # v2 minor 8/row 11.13: an ACCEPTED proposal's own validator verdict
      # used to be attached only to `result[:proposal]`, which nothing reads
      # - an accepted proposal that invalidates the whole graph bricked
      # every later dispatch with `invalid_graph` and left no record of why.
      # Reported through the same Findings channel the executor's own
      # findings already use, so it survives in the intent record.
      if proposal_result[:ok] && proposal_result[:validator] && !proposal_result[:validator][:ok]
        verdict_errors = Array(proposal_result[:validator][:errors]).join("; ")
        append_findings(intent_dir, node, ["accepted proposal invalidates the graph: #{verdict_errors}"], now: now)
      end
    end

    # 3. scope --------------------------------------------------------------
    checks_ran << "scope"
    changed = worktree.changed_paths(context, node: node, kind: kind, runner: runner)
    if changed.nil?
      return finish.call(fail_check(savepoint_path, context, node, "scope_unmeasurable", checks_ran, holder, extra_fields, now, ledger))
    end
    scope_reason = scope_violation(kind, changed, declared_files)
    if scope_reason
      return finish.call(fail_check(savepoint_path, context, node, scope_reason, checks_ran, holder, extra_fields, now, ledger))
    end

    # 4. named_tests ----------------------------------------------------------
    checks_ran << "named_tests"
    if missing_named_tests?(context, node, kind, worktree)
      return finish.call(fail_check(savepoint_path, context, node, "named_test_missing", checks_ran, holder, extra_fields, now, ledger))
    end

    # 5. merge ------------------------------------------------------------------
    # M2: `merge` lands in gates= only when a merge actually ran - a verify
    # or research return never reaches a merge (only a work node's diff
    # lives on a mergeable branch), so its evidence line must say `merge:none`
    # rather than claiming a check the code skipped for its kind.
    merge_commit = nil
    if kind.to_s == "work"
      checks_ran << "merge"
      merge_result = worktree.merge(context, node: node, runner: runner)
      unless merge_result[:ok]
        conflicted = Array(merge_result[:conflicted])
        if conflicted.empty?
          return finish.call(fail_check(savepoint_path, context, node, "merge_failed", checks_ran, holder, extra_fields, now, ledger))
        end

        outside = conflicted.reject { |p| path_covered?(p, declared_files) }
        if outside.empty?
          return finish.call(fail_check(savepoint_path, context, node, "merge_conflict", checks_ran, holder, extra_fields, now, ledger))
        end

        question = "merge conflict touches path(s) outside files: #{outside.sort.join(', ')}"
        fields = { question: question, holder: holder, gates: checks_ran.join("+") }.merge(extra_fields)
        return finish.call(write_transition(savepoint_path, context, node, "needs_decision", fields, now: now, ledger: ledger))
      end
      merge_commit = merge_result[:commit]
    else
      checks_ran << "merge:none"
    end

    # 6. suite --------------------------------------------------------------
    checks_ran << "suite"
    command = project_reader.call(intent_dir)
    if command == UNREADABLE_VERIFY_COMMAND
      # M1: a project.yml that fails to parse is not the same fact as a
      # project with no verify command at all - the record is broken, so the
      # node blocks rather than proceeding to `done` with `suite:absent`.
      #
      # v2 NEW-3: `gates=` must say `suite:unreadable`, never the bare
      # `suite` `checks_ran` already carries - the suite check itself never
      # ran, so claiming it did is M2's exact defect, reintroduced on the
      # state M1 added.
      gates = (checks_ran[0..-2] + ["suite:unreadable"]).join("+")
      fields = { reason: "verify_command_unreadable", gates: gates, holder: holder }.merge(extra_fields)
      return finish.call(write_transition(savepoint_path, context, node, "blocked", fields, now: now, ledger: ledger))
    end
    if command.nil?
      gates = (checks_ran[0..-2] + ["suite:absent"]).join("+")
      suite_value = "none"
    else
      suite_result = suite_runner.call(dir: context.worktree, command: command)
      unless suite_result[:ok]
        fields = { reason: "suite_red", gates: checks_ran.join("+"), holder: holder,
                   suite: format_suite(suite_result) }.merge(extra_fields)
        return finish.call(write_transition(savepoint_path, context, node, "failed_verification", fields, now: now, ledger: ledger))
      end
      gates = checks_ran.join("+")
      suite_value = format_suite(suite_result)
    end

    commit_value = merge_commit || parsed.commit
    fields = { gates: gates, commit: commit_value, holder: holder, suite: suite_value }.merge(extra_fields)
    result = write_transition(savepoint_path, context, node, "done", fields, now: now, ledger: ledger)

    worktree.release(context, node: node, state: "done", runner: runner) if result[:written]

    finish.call(result)
  end

  # --- transitions -------------------------------------------------------------

  def fail_check(savepoint_path, context, node, reason, checks_ran, holder, extra_fields, now, ledger)
    fields = { reason: reason, gates: checks_ran.join("+"), holder: holder }.merge(extra_fields)
    write_transition(savepoint_path, context, node, "failed_verification", fields, now: now, ledger: ledger)
  end
  private_class_method :fail_check

  def refused(reason)
    { state: "refused", written: false, reason: reason, gates: "", fields: {} }
  end
  private_class_method :refused

  # Appends the one transition line, catching GuardedAppend::Unavailable
  # rather than letting it escape (row 4.40): an append that fails AFTER a
  # merge has already landed on the intent branch must still report that
  # merge commit, so the node stays recoverable rather than looking like
  # nothing happened at all. Re-renders graph.md's ## Status after a
  # successfully written line (row 4.44, D28) - RunnerCore already owns that
  # render, this is its only production caller today.
  #
  # v2 NEW-1/row 11.2: `squash_prose` (below) removes every raw tab and
  # newline before a value ever reaches here, but nothing guarantees that is
  # the ONLY way a return's own prose can make `NodeLedger.transition_line`
  # refuse it (`ArgumentError`, raised before any file is ever touched) - a
  # pathological return must still land a transition, not crash the whole
  # step and leave the node stuck `running` until its lease expires. Falls
  # back to `blocked reason=return_unwritable`, whose own fields are all
  # runner-owned strings, never executor prose, so the fallback write itself
  # can never hit the same wall.
  def write_transition(savepoint_path, context, node, state, fields, now:, ledger:)
    result = ledger.append_transition(savepoint_path, subject: node, state: state, fields: fields, now: now)
  rescue GuardedAppend::Unavailable => e
    { state: "append_failed", written: false, fields: fields, gates: fields[:gates],
      commit: fields[:commit], error: e.message }
  rescue ArgumentError => e
    # 340b n8, row 8.11: this fallback still merges no caller `extra_fields`
    # (unchanged from before this node), but `fields[:harness]` is read
    # straight off the fields hash the failed write attempted, which already
    # carries `harness` whenever the caller's own `extra_fields` had it -
    # `.compact` drops the key rather than writing it empty when it did not.
    fallback_fields = { reason: "return_unwritable", holder: fields[:holder], gates: fields[:gates],
                         harness: fields[:harness] }.compact
    fallback = begin
      ledger.append_transition(savepoint_path, subject: node, state: "blocked", fields: fallback_fields, now: now)
    rescue GuardedAppend::Unavailable
      :unavailable
    end
    written = fallback == :written
    safe_render_status(context) if written
    { state: "blocked", written: written, fields: fallback_fields, gates: fallback_fields[:gates], commit: nil,
      error: e.message }
  else
    written = result == :written
    safe_render_status(context) if written
    { state: state, written: written, fields: fields, gates: fields[:gates], commit: fields[:commit] }
  end
  private_class_method :write_transition

  # v2 NEW-5/row 11.9: `RunnerCore.render_status` re-reads and re-parses
  # graph.md from scratch (never trusting `context.graph`, resolved once
  # before this step started) purely to rewrite its own ## Status table - a
  # cosmetic, best-effort render, not evidence. A `graph.md` that turned
  # unreadable mid-step (or was already unreadable, on a node whose kind
  # this call's own NEW-2 guard let through as `blocked`) must never turn a
  # transition ALREADY WRITTEN into a raw stack trace and a half-finished
  # step - the transition already landed in savepoint.md by the time this
  # runs, so a failed render is a missed cosmetic refresh, not a lost write.
  def safe_render_status(context)
    RunnerCore.render_status(context)
  rescue StandardError
    nil
  end
  private_class_method :safe_render_status

  # Collapse every run of whitespace (space, tab, newline, ...) in an
  # executor's own free text to a single space (v2 NEW-1): the ledger's own
  # field format is a single line, and `NodeLedger.normalize_value` raises
  # ArgumentError outright on a bare tab or newline rather than collapsing
  # it. A YAML block scalar is the natural way to write a two-sentence
  # question, so this runs on every `question:`/`reason:` before either
  # ever reaches a ledger field.
  def squash_prose(text)
    text.to_s.gsub(/\s+/, " ").strip
  end
  private_class_method :squash_prose

  def holder_for(entries, node)
    last = entries.select { |e| !e[:torn] && e[:subject] == node && e[:state] == "running" }.last
    last && (last[:fields] || {})["holder"]
  end
  private_class_method :holder_for

  # 340b n8/row 8.12: mirrors holder_for exactly - the value on the node's
  # OWN last `running` line, never a fresh resolve of the current session's
  # own harness. nil when that line carried none (row 8.13), which is what
  # keeps `extra_fields` from ever inventing the key.
  def harness_for(entries, node)
    last = entries.select { |e| !e[:torn] && e[:subject] == node && e[:state] == "running" }.last
    last && (last[:fields] || {})["harness"]
  end
  private_class_method :harness_for

  def drift_summary(integrity)
    parts = []
    parts << "drifted:#{integrity[:drifted].join(',')}" if Array(integrity[:drifted]).any?
    parts << "missing:#{integrity[:missing].join(',')}" if Array(integrity[:missing]).any?
    parts << (integrity[:reason] || "unknown") if parts.empty?
    parts.join(";")
  end
  private_class_method :drift_summary

  # --- scope ---------------------------------------------------------------

  def scope_violation(kind, changed, declared_files)
    case kind.to_s
    when "work"
      outside = Array(changed).reject { |p| path_covered?(p, declared_files) }
      outside.any? ? "diff_outside_files" : nil
    when "verify"
      Array(changed).any? ? "diff_on_verify_node" : nil
    when "research"
      Array(changed).any? ? "diff_on_research_node" : nil
    end
  end
  private_class_method :scope_violation

  def path_covered?(path, declared_files)
    norm = normalize_scope_path(path)
    declared_files.any? do |f|
      norm == f || norm.start_with?("#{f}/")
    end
  end
  private_class_method :path_covered?

  def normalize_files(files)
    Array(files).map { |f| normalize_scope_path(f) }
  end
  private_class_method :normalize_files

  def normalize_scope_path(path)
    path.to_s.sub(%r{\A\./}, "").sub(%r{/\z}, "")
  end
  private_class_method :normalize_scope_path

  # --- named tests -----------------------------------------------------------

  # Row 4.19/minor 1: read the node's own failure-mode matrix table, take
  # every `Test` cell's file basename AND method name (before/after the
  # `#`), and check both that `test/<basename>.rb` exists on the node's own
  # worktree - the tree the executor actually wrote to, not the not-yet-
  # merged intent tree - and that it actually DEFINES the named method
  # (post-execution review minor 1: proving only the file exists lets an
  # executor delete the test method while keeping its file and still pass
  # this gate). A node file that cannot be read, or that carries no such
  # section, names no tests and passes this check vacuously (nothing to
  # prove missing).
  def missing_named_tests?(context, node, kind, worktree)
    path = ReadySet.find_node_path(context.intent_dir, node)
    return false unless path

    nf = NodeFile.parse(path)
    return false unless nf[:ok]

    section = NodeFile.split_by_headings(nf[:body]).find { |(heading, _)| heading.to_s =~ /failure-mode matrix/i }
    return false unless section

    tests = NodeFile.table_rows(section[1]).filter_map do |row|
      cell = row[3]
      next nil if cell.to_s.strip.empty?

      basename, method = cell.gsub("`", "").split("#", 2)
      next nil if basename.to_s.strip.empty?

      [basename.strip, method.to_s.strip]
    end.uniq
    return false if tests.empty?

    check_dir = kind.to_s == "work" ? (worktree.paths(context, node: node) || {})["path"] : context.worktree
    return false if check_dir.nil?

    tests.any? do |basename, method|
      test_path = File.join(check_dir, "test", "#{basename}.rb")
      !File.exist?(test_path) || !method_defined_in_file?(test_path, method)
    end
  end
  private_class_method :missing_named_tests?

  # true when `method` is blank (a matrix row that names only a file, no
  # `#method`, still passes on file presence alone) or when `path`'s own
  # source text defines it. A source-text check, not a `require` and
  # introspect: loading an untrusted executor-written test file as living
  # Ruby is not a check RunnerAbsorb should ever perform.
  def method_defined_in_file?(path, method)
    return true if method.to_s.empty?
    return false unless File.exist?(path)

    File.read(path).match?(/^\s*def\s+#{Regexp.escape(method)}\b/)
  rescue StandardError
    false
  end
  private_class_method :method_defined_in_file?

  # --- findings --------------------------------------------------------------

  # One capped bullet under `### Findings` (D16), created under `## Insights`
  # when either heading is absent (row 4.35): Insights.append_insight never
  # creates a nested subsection, so this is its own small insertion, not a
  # call into that module.
  #
  # v2 NEW-4: this is a mid-file rewrite (a `## Links` section commonly
  # follows `### Findings`), so it goes through AtomicWrite directly -
  # sibling-temp-plus-rename, the same shape every other writer in this tree
  # uses (D19r) - which is genuine crash safety: a process that dies mid-
  # write leaves the ORIGINAL file untouched, never a half-written one.
  #
  # It is NOT mutual exclusion, and no longer pretends to be one. The
  # previous shape opened this same path under GuardedAppend's flock first
  # and called AtomicWrite.write from inside that hold - but flock guards
  # one open file HANDLE, and AtomicWrite's own rename puts a brand new
  # inode at the path underneath it. A second writer that opened its handle
  # before the rename keeps the OLD, now-unlinked inode; once the first
  # writer unlocks, the second takes a lock that excludes nobody, reads
  # stale content off the orphaned inode, and its own rename overwrites the
  # first writer's already-landed bullet - reproduced with two real
  # processes. `Insights.append_insight` (this module's sibling for the same
  # file) takes no lock at all either, so a bigger lock here would still
  # lose the race against that path. Findings are best-effort (D16): a lost
  # bullet under real concurrency is an accepted gap, not a promise this
  # method makes and breaks.
  def append_findings(intent_dir, node, findings, now:, renamer: File.method(:rename))
    return if Array(findings).empty?

    joined = Array(findings).join("; ")
    text = joined.length > FINDING_CAP ? "#{joined[0...(FINDING_CAP - 3)].rstrip}..." : joined
    bullet = "- [#{node}] #{text}"

    path = Savepoint.intent_file(intent_dir)
    content = File.exist?(path) ? File.read(path) : ""
    AtomicWrite.write(path, insert_finding_bullet(content, bullet), renamer: renamer)
    nil
  rescue StandardError
    nil
  end
  private_class_method :append_findings

  def insert_finding_bullet(content, bullet)
    lines = content.empty? ? [] : content.split("\n", -1)
    insights_idx = lines.index { |l| l.strip == "## Insights" }

    if insights_idx.nil?
      body = lines.join("\n")
      body = body.sub(/\n+\z/, "") unless body.empty?
      pieces = body.empty? ? [] : [body, ""]
      pieces.concat(["## Insights", "", "### Findings", bullet])
      return "#{pieces.join("\n")}\n"
    end

    idx = insights_idx + 1
    findings_idx = nil
    while idx < lines.length && !lines[idx].start_with?("## ")
      findings_idx = idx if lines[idx].strip == "### Findings"
      idx += 1
    end
    insights_end = idx

    # M12: `split("\n", -1)` keeps a trailing "" element exactly when
    # `content` itself ends in a newline (the file's own trailing newline
    # made visible as an array slot). When Insights is the LAST section (no
    # further "## " heading), `insights_end` walks all the way to
    # `lines.length`, merging that sentinel INTO the section - the very next
    # insert then landed AFTER it, turning the file's trailing newline into
    # a spurious blank line and leaving the new bullet as the final element
    # with no newline of its own. Excluding the sentinel here restores both:
    # the bullet lands where content actually ends, one newline intact.
    insights_end -= 1 if insights_end == lines.length && lines.last == ""

    if findings_idx
      fidx = findings_idx + 1
      fidx += 1 while fidx < insights_end && !lines[fidx].start_with?("#")
      lines.insert(fidx, bullet)
    else
      lines.insert(insights_end, "", "### Findings", bullet)
    end
    lines.join("\n")
  end
  private_class_method :insert_finding_bullet

  # --- the return file itself -------------------------------------------------

  def read_return_text(return_path)
    File.exist?(return_path.to_s) ? File.read(return_path.to_s) : ""
  end
  private_class_method :read_return_text

  # Row 4.42: the return is kept beside the packet at
  # packets/<node>--a<N>.return - copied there when `return_path` names
  # somewhere else, left alone when it already is that file.
  def preserve_return_file(intent_dir, node, attempt, return_path, text)
    target = NodeInput.packet_path(intent_dir: intent_dir, node: node, attempt: attempt).sub(/\.packet\z/, ".return")
    return target if File.expand_path(return_path.to_s) == File.expand_path(target)

    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, text) unless File.exist?(target) && File.read(target) == text
    target
  end
  private_class_method :preserve_return_file

  # --- the suite ---------------------------------------------------------------

  # v1 minor 7/row 11.17: reads the LAST summary line, not the first match -
  # a suite command that shells out to more than one sub-process (or prints
  # its own retry) can carry an earlier RED summary line before the one that
  # actually decided its exit status, and `.match` (first match) would
  # record that earlier line's counts on the `done` line instead.
  def default_suite_runner(dir:, command:)
    out, err, status = Open3.capture3(command, chdir: dir.to_s)
    combined = "#{out}\n#{err}"
    matches = combined.scan(/(\d+)\s+runs,\s+(\d+)\s+assertions,\s+(\d+)\s+failures,\s+(\d+)\s+errors/)
    return { ok: false, runs: nil, assertions: nil, failures: nil, errors: nil } if matches.empty?

    runs, assertions, failures, errors = matches.last.map(&:to_i)
    { ok: status.success? && failures.zero? && errors.zero?, runs: runs, assertions: assertions,
      failures: failures, errors: errors }
  end

  def format_suite(result)
    "#{result[:runs]}/#{result[:assertions]}/#{result[:failures]}/#{result[:errors]}"
  end
  private_class_method :format_suite

  # Own, lightweight equivalent of InstallerCore's private project reader
  # (that class needs a full instance to call its own copy): reads
  # project.yml's release.verify for the project this intent belongs to,
  # nil for a global-store-only intent or a project record with none
  # recorded (row 4.39's absent-command case). M1/row 9.14: a project.yml
  # that EXISTS but fails to parse returns UNREADABLE_VERIFY_COMMAND, never
  # nil - that record is broken, not merely silent on a verify command, and
  # the caller must not read the two the same way.
  def default_project_reader(intent_dir)
    m = intent_dir.to_s.match(PROJECT_LAYOUT_RE)
    return nil unless m

    home, slug = m[1], m[2]
    path = File.join(home, "projects", slug, "project.yml")
    return nil unless File.exist?(path)

    data = begin
      YAML.safe_load(File.read(path), permitted_classes: [Date, Time])
    rescue StandardError
      return UNREADABLE_VERIFY_COMMAND
    end
    # v2 minor 13/row 11.15: a project.yml that PARSES cleanly but to
    # something other than a mapping (an empty file, a bare string, a list)
    # is the same broken-record fact as one that fails to parse outright -
    # M1's whole point was that a broken record must never read the same as
    # "no verify command declared", and reading a non-Hash as nil silently
    # reopened that exact gap.
    return UNREADABLE_VERIFY_COMMAND unless data.is_a?(Hash)

    release = data["release"]
    return nil unless release.is_a?(Hash)

    verify = release["verify"]
    return nil unless verify.is_a?(String) && !verify.strip.empty?

    verify.split("\n").map(&:strip).reject(&:empty?).join("; ")
  end
end
