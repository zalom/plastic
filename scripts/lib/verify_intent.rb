# encoding: UTF-8
# frozen_string_literal: true

require_relative "worktree"
require_relative "scaffold_intent"

# VerifyIntent - all logic for `scripts/verify-intent` (intent 213). Bundles the checks that
# need no project-specific knowledge into one verdict: the per-intent doctor scan
# (`Doctor#run_intent_check`), a net-new added-line em-dash diff guard (the first standing
# implementation of this check; the only prior automated em-dash check,
# `test/skill_command_lint_test.rb`, asserts against two FIXED file sets and cannot scan a
# diff), a diffstat, and an optional caller-supplied `--suite` command folded into the same
# verdict.
#
# Repo resolution and base-branch detection are NOT re-implemented here: `resolve_repo_dir`,
# `detect_base_branch`, and `diffstat` are `ScaffoldIntent`'s own shared git seam helpers
# (built for `scripts/scaffold-intent`, intent 213 ACTION_2); this module calls them so
# there is exactly one implementation of each in the repo.
#
# Pure and dependency-injected: never calls `exit` or `abort`, never reads `ARGV`. The public
# entry point (`run`) returns a verdict hash; `scripts/verify-intent` maps it to stdout lines
# plus an exit code. Seams: `git_runner:` (defaults to `Worktree::ShellRunner.new`),
# `doctor:` (a lambda, defaults to a real `Doctor#run_intent_check` call), `suite_runner:` (a
# lambda, defaults to a real subprocess with `RUBYOPT` cleared).
module VerifyIntent
  module_function

  # Built from its codepoint, never typed as a literal byte, so this file's own source stays
  # free of the character it is written to detect (matching scripts/end-intent's own
  # EM_DASH constant, built the same way).
  EM_DASH = "\u2014"

  EXIT_OK = 0
  EXIT_USAGE = 1
  EXIT_DOCTOR = 2
  EXIT_EMDASH = 3
  EXIT_SUITE = 4

  # --- entry point ---------------------------------------------------------------

  def run(store:, id:, base: nil, suite: nil, home: Dir.home,
          git_runner: Worktree::ShellRunner.new, doctor: default_doctor, suite_runner: default_suite_runner)
    return usage_result("--store is required") if Worktree.blank?(store)
    return usage_result("--id is required") if Worktree.blank?(id)

    intent_dir, resolve_err = ScaffoldIntent.resolve_intent_dir(store, id)
    return usage_result(resolve_err) if intent_dir.nil?

    gate_home, scope = resolve_plastic_home_and_scope(store)

    lines = []
    checks = {}
    codes = []

    doctor_lines, doctor_code, doctor_check = run_doctor_check(home: gate_home, scope: scope, id: id, doctor: doctor)
    lines.concat(doctor_lines)
    checks[:doctor] = doctor_check
    codes << doctor_code if doctor_code

    repo = ScaffoldIntent.resolve_repo_dir(store: store, id: id, intent_dir: intent_dir, home: home, runner: git_runner)
    base_ref = base
    base_ref ||= repo ? ScaffoldIntent.detect_base_branch(repo, runner: git_runner) : nil

    emdash_lines, emdash_code, emdash_check = run_emdash_check(repo: repo, base: base_ref, git_runner: git_runner)
    lines.concat(emdash_lines)
    checks[:emdash] = emdash_check
    codes << emdash_code if emdash_code

    diffstat_lines, diffstat_check = run_diffstat_check(repo: repo, base: base_ref, git_runner: git_runner)
    lines.concat(diffstat_lines)
    checks[:diffstat] = diffstat_check

    report_lines_out, report_check = run_report_lines_check(intent_dir: intent_dir)
    lines.concat(report_lines_out)
    checks[:report] = report_check

    if Worktree.blank?(suite)
      checks[:suite] = { status: "skipped" }
    else
      suite_lines, suite_code, suite_check = run_suite_check(suite: suite, repo: repo, suite_runner: suite_runner)
      lines.concat(suite_lines)
      checks[:suite] = suite_check
      codes << suite_code if suite_code
    end

    { exit_code: codes.compact.min || EXIT_OK, lines: lines, checks: checks }
  end

  def usage_result(message)
    { exit_code: EXIT_USAGE, lines: ["verify-intent: #{message}"], checks: {} }
  end

  # --- store/scope resolution (mirrors scripts/end-intent:161-170) ---------------

  # `store` is `<plastic_home>/store` or `<plastic_home>/projects/<slug>/store`. The two
  # shapes are told apart by whether store's grandparent is literally named "projects" (the
  # StoreDiscovery convention), never by hardcoding ".plastic" as a name.
  def resolve_plastic_home_and_scope(store)
    parent = File.dirname(store)
    grandparent = File.dirname(parent)
    if File.basename(grandparent) == "projects"
      [File.dirname(grandparent), "project:#{File.basename(parent)}"]
    else
      [parent, "global"]
    end
  end

  # --- check 1: doctor, scoped to the intent --------------------------------------

  def default_doctor
    lambda do |home:, scope:, id:|
      require_relative "../doctor"
      Doctor.new(plastic_home: home, runner: Doctor.default_runner).run_intent_check(id, store: scope)
    end
  end

  # Fail-open on any crash (a broken diagnostic must never wedge a verify): the check is
  # skipped, not failed.
  def run_doctor_check(home:, scope:, id:, doctor:)
    verdict = doctor.call(home: home, scope: scope, id: id)
    case verdict[:status]
    when "fail"
      failing = Array(verdict[:checks]).select { |c| c[:status] == "fail" }
      lines = failing.map { |c| "doctor: FAIL #{c[:name]}: #{c[:message]}" }
      lines = ["doctor: FAIL"] if lines.empty?
      [lines, EXIT_DOCTOR, { status: "fail", verdict: verdict }]
    when "warn"
      warning = Array(verdict[:checks]).select { |c| c[:status] == "warn" }
      lines = warning.map { |c| "doctor: WARN #{c[:name]}: #{c[:message]}" }
      lines = ["doctor: WARN"] if lines.empty?
      [lines, nil, { status: "warn", verdict: verdict }]
    else
      [["doctor: pass"], nil, { status: "pass", verdict: verdict }]
    end
  rescue StandardError => e
    [["doctor crashed (#{e.message}); proceeding without it"], nil, { status: "crashed", error: e.message }]
  end

  # --- check 2: the added-line em-dash diff guard (net-new, D9) -------------------

  # Store and intent files are exempt from the no-em-dash rule (AGENTS.md states this
  # explicitly), and INDEX.md is REQUIRED to carry a real em dash on write
  # (scripts/end-intent:82-88). No per-file allow-list beyond these three shapes.
  def exempt_path?(path)
    return true if path.nil?
    return true if path.start_with?("store/")
    return true if path.split("/").include?(".plastic")
    return true if path == "INDEX.md" || path.end_with?("/INDEX.md")
    return true if path.start_with?("test/fixtures/")

    false
  end

  HUNK_HEADER_RE = /\A@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@/

  # Scan ONLY the added lines of a unified diff (never a removed line, never a context
  # line, never the `+++ ` file header line itself). An added line starts with exactly one
  # `+` and is not the file header; per the spec this is decided with
  # `l.start_with?("+") && !l.start_with?("+++")`. Tracks the current file from the most
  # recent `+++ b/<path>` header and the current new-file line number from the most recent
  # `@@ -a,b +c,d @@` hunk header, incrementing on every context or added line (never on a
  # removed line, which does not exist in the new file).
  def em_dash_violations(diff_text)
    violations = []
    current_file = nil
    current_line = nil
    exempt = false

    diff_text.to_s.each_line do |line|
      if line.start_with?("+++")
        current_file = line.sub(/\A\+\+\+\s*/, "").strip.sub(%r{\Ab/}, "")
        exempt = exempt_path?(current_file)
        next
      end

      if (m = line.match(HUNK_HEADER_RE))
        current_line = m[1].to_i
        next
      end

      if line.start_with?("+")
        text = line[1..].to_s.chomp
        violations << { file: current_file, line: current_line, text: text } if !exempt && text.include?(EM_DASH)
        current_line += 1 if current_line
      elsif line.start_with?("-")
        # A removed line does not exist in the new file: never scanned, never counted.
      elsif line.start_with?(" ")
        current_line += 1 if current_line
      end
    end

    violations
  end

  def run_emdash_check(repo:, base:, git_runner:)
    if repo.nil?
      return [["em-dash guard skipped: no repo could be resolved for this intent"], nil,
              { status: "skipped", reason: "no repo" }]
    end
    if base.nil?
      return [["em-dash guard skipped: no base branch could be detected (no origin/HEAD, main, or master)"], nil,
              { status: "skipped", reason: "no base" }]
    end

    res = git_runner.run("-C", repo, "diff", "#{base}...HEAD")
    unless res.success?
      reason = res.stderr.to_s.strip
      return [["em-dash guard skipped: #{reason}"], nil, { status: "skipped", reason: reason }]
    end

    violations = em_dash_violations(res.stdout)
    if violations.empty?
      [["em-dash guard: pass (0 violations)"], nil, { status: "pass", violations: [] }]
    else
      lines = ["em-dash guard: #{violations.size} violation(s) found"]
      lines.concat(violations.map { |v| "#{v[:file]}:#{v[:line]}: #{v[:text]}" })
      [lines, EXIT_EMDASH, { status: "fail", violations: violations }]
    end
  end

  # --- check 3: the diffstat -------------------------------------------------------

  def run_diffstat_check(repo:, base:, git_runner:)
    if repo.nil?
      return [["diffstat unavailable: no repo could be resolved for this intent"], { status: "skipped" }]
    end
    if base.nil?
      return [["diffstat unavailable: no base branch could be detected (no origin/HEAD, main, or master)"],
              { status: "skipped" }]
    end

    stat, err = ScaffoldIntent.diffstat(repo, base, runner: git_runner)
    if stat.nil?
      [["diffstat unavailable: #{err}"], { status: "skipped" }]
    else
      lines = ["diffstat against #{base}:"]
      lines.concat(stat.each_line.map(&:chomp))
      [lines, { status: "pass", stat: stat }]
    end
  end

  # --- check: the Report savepoint lines (intent 331f, F17) ------------------------

  REPORT_LINE_RE = /\A(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ)\s{2,}(\S+)\s{2,}(.+?)\s*\z/.freeze

  # Every `Report`-kind savepoint line for this intent, oldest first: [timestamp, text].
  # Never fails or gates anything (D3: the diffstat check already prints a summary block,
  # this folds into the same verdict so verify-intent surfaces them too) - a delivery with
  # no Report line is visible to `doctor`'s intent_reports_printed_check instead.
  def report_lines(intent_dir)
    path = File.join(intent_dir, "savepoint.md")
    return [] unless File.exist?(path)

    File.readlines(path).filter_map do |line|
      m = line.strip.match(REPORT_LINE_RE)
      next nil unless m && m[2] == "Report"
      [m[1], m[3]]
    end
  end

  def run_report_lines_check(intent_dir:)
    entries = report_lines(intent_dir)
    if entries.empty?
      [["report lines: none recorded"], { status: "pass", lines: [] }]
    else
      lines = ["report lines:"] + entries.map { |ts, text| "#{ts}  Report  #{text}" }
      [lines, { status: "pass", lines: entries }]
    end
  end

  # --- check 4: the optional suite --------------------------------------------------

  # The supplied command is very likely a ruby command, so it is spawned with RUBYOPT
  # cleared, matching the pattern at scripts/maintenance-run:133.
  def default_suite_runner
    lambda do |command, dir|
      require "open3"
      out, status = Open3.capture2e({ "RUBYOPT" => nil }, command, chdir: dir || Dir.pwd)
      [out, status.exitstatus]
    end
  end

  def run_suite_check(suite:, repo:, suite_runner:)
    output, status = suite_runner.call(suite, repo)
    lines = ["suite: #{suite}"]
    lines.concat(output.to_s.each_line.map(&:chomp))
    lines << "suite: exit #{status}"

    if status.to_i.zero?
      [lines, nil, { status: "pass", exit_status: status }]
    else
      [lines, EXIT_SUITE, { status: "fail", exit_status: status }]
    end
  end
end
