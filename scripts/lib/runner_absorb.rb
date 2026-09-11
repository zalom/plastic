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
require_relative "node_packet"
require_relative "ready_set"
require_relative "core_integrity"
require_relative "runner_core"
require_relative "worktree"
require_relative "insights"
require_relative "savepoint"
require_relative "guarded_append"

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
             project_reader: method(:default_project_reader))
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
    node_decl = ((context.graph || {})[:nodes] || {})[node] || {}
    kind = node_decl[:kind]
    declared_files = normalize_files(node_decl[:files])

    checks_ran = []
    extra_fields = {}

    # 1. integrity ------------------------------------------------------------
    checks_ran << "integrity"
    integrity = integrity_checker.call(plastic_home: context.plastic_home)
    unless integrity[:ok]
      if allow_core_drift
        extra_fields["allow_core_drift"] = "true"
      else
        fields = { reason: "core_integrity", core_drift: drift_summary(integrity), holder: holder,
                   gates: checks_ran.join("+") }
        return write_transition(savepoint_path, context, node, "blocked", fields, now: now, ledger: ledger)
      end
    end

    # 2. schema -----------------------------------------------------------------
    checks_ran << "schema"
    text = read_return_text(return_path)
    parsed = NodeReturn.parse(text)

    attempt = NodePacket.compute_attempt_number(intent_dir: intent_dir, node: node, lease_flag_given: false,
                                                 entries: entries)
    preserve_return_file(intent_dir, node, attempt, return_path, text)

    unless parsed.ok
      return fail_check(savepoint_path, context, node, "return_unparsable", checks_ran, holder, extra_fields, now, ledger)
    end
    if parsed.node != node
      return fail_check(savepoint_path, context, node, "node_mismatch", checks_ran, holder, extra_fields, now, ledger)
    end

    append_findings(intent_dir, node, parsed.findings, now: now)

    # B1: the return's own status governs from here on. The six mechanical
    # checks (3-6) exist to VERIFY a `done` claim, never to overrule an
    # executor's own report of its failure or its own open question - a
    # `needs_decision`, `blocked` or `failed_verification` return writes
    # exactly that state, carrying the field its own schema required
    # (`question` or `reason`), and stops here. Only `done` falls through.
    unless parsed.status == "done"
      fields = { holder: holder, gates: checks_ran.join("+") }.merge(extra_fields)
      fields[:question] = parsed.question if parsed.status == "needs_decision"
      fields[:reason] = parsed.reason if %w[blocked failed_verification].include?(parsed.status)
      return write_transition(savepoint_path, context, node, parsed.status, fields, now: now, ledger: ledger)
    end

    # 3. scope --------------------------------------------------------------
    checks_ran << "scope"
    changed = worktree.changed_paths(context, node: node, kind: kind, runner: runner)
    if changed.nil?
      return fail_check(savepoint_path, context, node, "scope_unmeasurable", checks_ran, holder, extra_fields, now, ledger)
    end
    scope_reason = scope_violation(kind, changed, declared_files)
    if scope_reason
      return fail_check(savepoint_path, context, node, scope_reason, checks_ran, holder, extra_fields, now, ledger)
    end

    # 4. named_tests ----------------------------------------------------------
    checks_ran << "named_tests"
    if missing_named_tests?(context, node, kind, worktree)
      return fail_check(savepoint_path, context, node, "named_test_missing", checks_ran, holder, extra_fields, now, ledger)
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
          return fail_check(savepoint_path, context, node, "merge_failed", checks_ran, holder, extra_fields, now, ledger)
        end

        outside = conflicted.reject { |p| path_covered?(p, declared_files) }
        if outside.empty?
          return fail_check(savepoint_path, context, node, "merge_conflict", checks_ran, holder, extra_fields, now, ledger)
        end

        question = "merge conflict touches path(s) outside files: #{outside.sort.join(', ')}"
        fields = { question: question, holder: holder, gates: checks_ran.join("+") }.merge(extra_fields)
        return write_transition(savepoint_path, context, node, "needs_decision", fields, now: now, ledger: ledger)
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
      fields = { reason: "verify_command_unreadable", gates: checks_ran.join("+"), holder: holder }.merge(extra_fields)
      return write_transition(savepoint_path, context, node, "blocked", fields, now: now, ledger: ledger)
    end
    if command.nil?
      gates = (checks_ran[0..-2] + ["suite:absent"]).join("+")
      suite_value = "none"
    else
      suite_result = suite_runner.call(dir: context.worktree, command: command)
      unless suite_result[:ok]
        fields = { reason: "suite_red", gates: checks_ran.join("+"), holder: holder,
                   suite: format_suite(suite_result) }.merge(extra_fields)
        return write_transition(savepoint_path, context, node, "failed_verification", fields, now: now, ledger: ledger)
      end
      gates = checks_ran.join("+")
      suite_value = format_suite(suite_result)
    end

    commit_value = merge_commit || parsed.commit
    fields = { gates: gates, commit: commit_value, holder: holder, suite: suite_value }.merge(extra_fields)
    result = write_transition(savepoint_path, context, node, "done", fields, now: now, ledger: ledger)

    worktree.release(context, node: node, state: "done", runner: runner) if result[:written]

    result
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
  def write_transition(savepoint_path, context, node, state, fields, now:, ledger:)
    result = ledger.append_transition(savepoint_path, subject: node, state: state, fields: fields, now: now)
  rescue GuardedAppend::Unavailable => e
    { state: "append_failed", written: false, fields: fields, gates: fields[:gates],
      commit: fields[:commit], error: e.message }
  else
    written = result == :written
    RunnerCore.render_status(context) if written
    { state: state, written: written, fields: fields, gates: fields[:gates], commit: fields[:commit] }
  end
  private_class_method :write_transition

  def holder_for(entries, node)
    last = entries.select { |e| !e[:torn] && e[:subject] == node && e[:state] == "running" }.last
    last && (last[:fields] || {})["holder"]
  end
  private_class_method :holder_for

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

  # Row 4.19: read the node's own failure-mode matrix table, take every
  # `Test` cell's file basename (before the `#`), and check that
  # `test/<basename>.rb` exists on the node's own worktree - the tree the
  # executor actually wrote to, not the not-yet-merged intent tree. A node
  # file that cannot be read, or that carries no such section, names no
  # tests and passes this check vacuously (nothing to prove missing).
  def missing_named_tests?(context, node, kind, worktree)
    path = ReadySet.find_node_path(context.intent_dir, node)
    return false unless path

    nf = NodeFile.parse(path)
    return false unless nf[:ok]

    section = NodeFile.split_by_headings(nf[:body]).find { |(heading, _)| heading.to_s =~ /failure-mode matrix/i }
    return false unless section

    basenames = NodeFile.table_rows(section[1]).filter_map do |row|
      cell = row[3]
      next nil if cell.to_s.strip.empty?

      cell.gsub("`", "").split("#").first
    end.uniq
    return false if basenames.empty?

    check_dir = kind.to_s == "work" ? (worktree.paths(context, node: node) || {})["path"] : context.worktree
    return false if check_dir.nil?

    basenames.any? { |b| !File.exist?(File.join(check_dir, "test", "#{b}.rb")) }
  end
  private_class_method :missing_named_tests?

  # --- findings --------------------------------------------------------------

  # One capped bullet under `### Findings` (D16), created under `## Insights`
  # when either heading is absent (row 4.35): Insights.append_insight never
  # creates a nested subsection, so this is its own small insertion, not a
  # call into that module.
  def append_findings(intent_dir, node, findings, now:)
    return if Array(findings).empty?

    joined = Array(findings).join("; ")
    text = joined.length > FINDING_CAP ? "#{joined[0...(FINDING_CAP - 3)].rstrip}..." : joined
    bullet = "- [#{node}] #{text}"

    path = Savepoint.intent_file(intent_dir)
    content = File.exist?(path) ? File.read(path) : ""
    File.write(path, insert_finding_bullet(content, bullet))
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
    target = NodePacket.packet_path(intent_dir: intent_dir, node: node, attempt: attempt).sub(/\.packet\z/, ".return")
    return target if File.expand_path(return_path.to_s) == File.expand_path(target)

    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, text) unless File.exist?(target) && File.read(target) == text
    target
  end
  private_class_method :preserve_return_file

  # --- the suite ---------------------------------------------------------------

  def default_suite_runner(dir:, command:)
    out, err, status = Open3.capture3(command, chdir: dir.to_s)
    combined = "#{out}\n#{err}"
    m = combined.match(/(\d+)\s+runs,\s+(\d+)\s+assertions,\s+(\d+)\s+failures,\s+(\d+)\s+errors/)
    return { ok: false, runs: nil, assertions: nil, failures: nil, errors: nil } unless m

    runs, assertions, failures, errors = m.captures.map(&:to_i)
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
    return nil unless data.is_a?(Hash)

    release = data["release"]
    return nil unless release.is_a?(Hash)

    verify = release["verify"]
    return nil unless verify.is_a?(String) && !verify.strip.empty?

    verify.split("\n").map(&:strip).reject(&:empty?).join("; ")
  end
end
