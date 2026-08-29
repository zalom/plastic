# encoding: UTF-8
# frozen_string_literal: true

require "fileutils"
require_relative "worktree"
require_relative "bridge"
require_relative "savepoint"
require_relative "intent_validator"

# ScaffoldIntent - all logic for `scripts/scaffold-intent` (intent 213). Three
# subcommands (spec|checklist|outcome), each writes one lifecycle artifact by copying or
# mechanically deriving it from an already-committed source: the intent file's
# `### Decisions` list, spec.md's `## Acceptance Criteria` list, or a `git diff --stat`
# plus an optional supplied test-summary file. No subcommand interprets or invents prose;
# a field this module cannot derive mechanically is left as the template's own stub text
# instead of being guessed at.
#
# `scaffold-intent` does not scaffold `actions/` in any form (intent 133a, D11): actions
# require judgment and stay entirely with the planner. No method here creates the
# directory, writes a `.gitkeep`, or writes a sentinel-only `ACTION_*.md`.
#
# Pure and dependency-injected: never calls `exit` or `abort`, never reads `ARGV` or
# `ENV` directly (only via the ambient `Dir.home` default, matching Bridge/Worktree
# convention). A git seam is injected as `runner:`, defaulting to
# `Worktree::ShellRunner.new`, so tests drive this in process with a fake runner and
# never touch real git. Every method returns a value; `scripts/scaffold-intent` maps the
# returned result to an exit code.
module ScaffoldIntent
  module_function

  SPEC_SECTIONS = [
    "## Problem", "## Goals", "## Non-Goals", "## Approach",
    "## Alternatives Considered", "## Decisions",
    "## Acceptance Criteria", "## Open Questions",
  ].freeze

  # --- path resolution (pure) --------------------------------------------------

  def expand(path)
    File.expand_path(path.to_s.sub(/\A~/, Dir.home))
  end

  # Resolve the single "<store>/<id>--*" directory. Returns [dir, nil] on success, or
  # [nil, message] on a usage failure (no match, or more than one match).
  def resolve_intent_dir(store, id)
    matches = Dir.glob(File.join(store, "#{id}--*")).select { |d| File.directory?(d) }
    return [nil, "no intent directory matches #{id}--* under #{store}"] if matches.empty?
    if matches.length > 1
      return [nil, "ambiguous id #{id.inspect}: #{matches.length} matching directories under #{store}"]
    end

    [matches.first, nil]
  end

  # The templates dir, resolved the same way from this file's own directory
  # (scripts/lib) as `scripts/scaffold-intent` resolves it from its own directory
  # (scripts/): two levels up. A repo checkout has templates/ at the repo root; an
  # installed copy has it at <plastic_home>/templates, which is also two levels up
  # from <plastic_home>/scripts/lib. The explicit `<plastic_home>/templates` fallback
  # covers the case where that computed path does not exist. Returns nil when neither
  # exists.
  def resolve_templates_dir(home: Dir.home)
    primary = File.expand_path("../../templates", __dir__)
    return primary if Dir.exist?(primary)

    fallback = File.expand_path(File.join(home, ".plastic", "templates"))
    return fallback if Dir.exist?(fallback)

    nil
  end

  def templates_missing_message(home: Dir.home)
    primary = File.expand_path("../../templates", __dir__)
    fallback = File.expand_path(File.join(home, ".plastic", "templates"))
    "no templates directory found; tried #{primary} and #{fallback}"
  end

  # --- result builders (pure) ---------------------------------------------------

  def ok_result(path)
    { status: :ok, code: 0, message: nil, path: path }
  end

  def refuse_result(path)
    { status: :refused, code: 2, path: path,
      message: "#{path} already has real content; pass --force to overwrite it deliberately" }
  end

  def error_result(message)
    { status: :error, code: 3, message: message, path: nil }
  end

  # True iff `target` exists, carries real (non-sentinel) content, and `force` was not
  # passed: the caller must refuse to write and leave the file untouched.
  def refuse_without_force?(target, force)
    File.exist?(target) && Savepoint.stage_file_present?(target) && !force
  end

  # --- generic section helpers (pure) --------------------------------------------

  # Split `text` into { "## Heading" => body_text } by top-level `## ` headings (never
  # `### `). Each body runs from the line after its heading to the line before the next
  # `## ` heading (or EOF), copied verbatim including any trailing blank line.
  def sections_from(text)
    sections = {}
    current = nil
    buf = []
    text.each_line do |line|
      if line.start_with?("## ")
        sections[current] = buf.join if current
        current = line.rstrip
        buf = []
      elsif current
        buf << line
      end
    end
    sections[current] = buf.join if current
    sections
  end

  # Replace the body of `heading` in `text` with `new_body_lines` (an Array of String
  # fragments), leaving every other line untouched. A no-op (returns `text` unchanged)
  # when `heading` is not found.
  def replace_section_body(text, heading, new_body_lines)
    lines = text.lines
    idx = lines.index { |l| l.rstrip == heading }
    return text if idx.nil?

    stop = idx + 1
    stop += 1 while stop < lines.length && !lines[stop].start_with?("## ")
    (lines[0..idx] + new_body_lines + lines[stop..]).join
  end

  # --- `### Decisions` extraction from the intent file (pure) --------------------

  # Byte-for-byte body of the first `### Decisions` heading in `intent_file_content`.
  # Returns [body, nil] on success, or [nil, message] when the heading is absent or its
  # body has no non-blank line.
  def extract_decisions(intent_file_content)
    lines = intent_file_content.lines
    idx = lines.index { |l| l.rstrip == "### Decisions" }
    return [nil, "the intent file has no ### Decisions list to copy; the Why stage is not finished"] if idx.nil?

    stop = idx + 1
    stop += 1 while stop < lines.length && !(lines[stop].start_with?("## ") || lines[stop].start_with?("### "))
    body_lines = lines[(idx + 1)...stop]
    body_lines = strip_blank_edges(body_lines)

    if body_lines.empty?
      return [nil, "the intent file's ### Decisions list has no content to copy; the Why stage is not finished"]
    end

    [body_lines.join, nil]
  end

  # --- `## Acceptance Criteria` extraction from spec.md (pure) --------------------

  # Byte-for-byte body of `## Acceptance Criteria` in `spec_content`. Returns
  # [body, nil] on success, or [nil, message] when the heading is absent or its body
  # holds no `- [ ]` line.
  def extract_acceptance_criteria(spec_content)
    lines = spec_content.lines
    idx = lines.index { |l| l.rstrip == "## Acceptance Criteria" }
    return [nil, "spec.md has no ## Acceptance Criteria section to copy"] if idx.nil?

    stop = idx + 1
    stop += 1 while stop < lines.length && !lines[stop].start_with?("## ")
    body_lines = strip_blank_edges(lines[(idx + 1)...stop])

    unless body_lines.any? { |l| l =~ /^\s*- \[ \]/ }
      return [nil, "spec.md's ## Acceptance Criteria has no checklist items (no line matching '- [ ]')"]
    end

    [body_lines.join, nil]
  end

  def strip_blank_edges(lines)
    lines = lines.drop_while { |l| l.strip.empty? }
    lines.reverse.drop_while { |l| l.strip.empty? }.reverse
  end

  # --- spec subcommand ------------------------------------------------------------

  def scaffold_spec(intent_dir:, force:, templates_dir: nil, home: Dir.home)
    target = File.join(intent_dir, "spec.md")
    return refuse_result(target) if refuse_without_force?(target, force)

    intent_file = Savepoint.intent_file(intent_dir)
    return error_result("the intent file is missing at #{intent_file}") unless File.exist?(intent_file)

    intent_content = File.read(intent_file)
    fm = IntentValidator.parse_frontmatter_text(intent_content)
    intent_name = fm.is_a?(Hash) ? fm["intent"] : nil
    if Bridge.blank?(intent_name)
      return error_result("the intent file at #{intent_file} has no frontmatter intent name")
    end

    decisions_body, decisions_err = extract_decisions(intent_content)
    return error_result(decisions_err) if decisions_body.nil?

    tdir = templates_dir || resolve_templates_dir(home: home)
    return error_result(templates_missing_message(home: home)) if tdir.nil?

    spec_template_path = File.join(tdir, "spec.md")
    return error_result("spec.md template not found at #{spec_template_path}") unless File.exist?(spec_template_path)

    written = build_spec_content(intent_name: intent_name, decisions_body: decisions_body,
                                  template_text: File.read(spec_template_path))

    FileUtils.mkdir_p(intent_dir)
    File.write(target, written)
    ok_result(target)
  end

  def build_spec_content(intent_name:, decisions_body:, template_text:)
    template_sections = sections_from(template_text)

    out = []
    out << "# Spec: #{intent_name}\n"
    out << "\n"

    SPEC_SECTIONS.each do |heading|
      out << "#{heading}\n"
      if heading == "## Decisions"
        out << decisions_body
        out << "\n"
      else
        out << (template_sections[heading] || "")
      end
    end

    out.join
  end

  # --- checklist subcommand --------------------------------------------------------

  def scaffold_checklist(intent_dir:, force:, templates_dir: nil, home: Dir.home)
    target = File.join(intent_dir, "checklist.md")
    return refuse_result(target) if refuse_without_force?(target, force)

    spec_path = File.join(intent_dir, "spec.md")
    unless File.exist?(spec_path) && Savepoint.stage_file_present?(spec_path)
      return error_result("spec.md is missing or still the scaffold placeholder at #{spec_path}")
    end

    ac_body, ac_err = extract_acceptance_criteria(File.read(spec_path))
    return error_result(ac_err) if ac_body.nil?

    intent_file = Savepoint.intent_file(intent_dir)
    fm = IntentValidator.parse_frontmatter(intent_file)
    intent_name = fm.is_a?(Hash) ? fm["intent"] : nil
    if Bridge.blank?(intent_name)
      return error_result("the intent file at #{intent_file} has no frontmatter intent name")
    end

    tdir = templates_dir || resolve_templates_dir(home: home)
    return error_result(templates_missing_message(home: home)) if tdir.nil?

    checklist_template_path = File.join(tdir, "checklist.md")
    unless File.exist?(checklist_template_path)
      return error_result("checklist.md template not found at #{checklist_template_path}")
    end

    template_text = File.read(checklist_template_path).sub("{{INTENT_NAME}}", intent_name)
    written = replace_section_body(template_text, "## In Progress", [ac_body, "\n"])

    FileUtils.mkdir_p(intent_dir)
    File.write(target, written)
    ok_result(target)
  end

  # --- repo / base-branch resolution (shared with ACTION_3) -----------------------

  # The provisioned code worktree for this intent when it exists on disk, else the git
  # toplevel of the current working directory. Returns nil when neither resolves.
  def resolve_repo_dir(store:, id:, intent_dir:, home: Dir.home, runner: Worktree::ShellRunner.new)
    wt_home = Worktree.home_from_store(store) || home
    slug = Worktree.slug_for_store(store, home: wt_home)
    intent_slug = File.basename(intent_dir).split("--", 2).last
    paths = Worktree.paths(slug: slug, intent_id: id, intent_slug: intent_slug, home: wt_home)
    code = paths["code"]
    return code if code && Dir.exist?(code)

    res = runner.run("-C", Dir.pwd, "rev-parse", "--show-toplevel")
    return nil unless res.success?

    top = res.stdout.to_s.strip
    top.empty? ? nil : top
  end

  # Standard git base-branch detection, first success wins: origin/HEAD, then `main`,
  # then `master`. Returns nil when none resolve.
  def detect_base_branch(repo, runner: Worktree::ShellRunner.new)
    res = runner.run("-C", repo, "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD")
    if res.success?
      ref = res.stdout.to_s.strip
      return ref.sub(%r{\Aorigin/}, "") unless ref.empty?
    end

    return "main" if runner.run("-C", repo, "rev-parse", "--verify", "--quiet", "main").success?
    return "master" if runner.run("-C", repo, "rev-parse", "--verify", "--quiet", "master").success?

    nil
  end

  # [stdout, nil] on success, [nil, stderr] on failure. Three-dot range so the diff is
  # against the merge base, not the tip of the base branch.
  def diffstat(repo, base, runner: Worktree::ShellRunner.new)
    res = runner.run("-C", repo, "diff", "--stat", "#{base}...HEAD")
    return [nil, res.stderr.to_s.strip] unless res.success?

    [res.stdout.to_s, nil]
  end

  # --- outcome subcommand -----------------------------------------------------------

  def scaffold_outcome(intent_dir:, force:, store:, id:, test_summary: nil,
                       home: Dir.home, runner: Worktree::ShellRunner.new, templates_dir: nil)
    target = File.join(intent_dir, "outcome.md")
    return refuse_result(target) if refuse_without_force?(target, force)

    intent_file = Savepoint.intent_file(intent_dir)
    return error_result("the intent file is missing at #{intent_file}") unless File.exist?(intent_file)

    fm = IntentValidator.parse_frontmatter(intent_file)
    intent_name = fm.is_a?(Hash) ? fm["intent"] : nil
    if Bridge.blank?(intent_name)
      return error_result("the intent file at #{intent_file} has no frontmatter intent name")
    end

    tdir = templates_dir || resolve_templates_dir(home: home)
    return error_result(templates_missing_message(home: home)) if tdir.nil?

    outcome_template_path = File.join(tdir, "outcome.md")
    unless File.exist?(outcome_template_path)
      return error_result("outcome.md template not found at #{outcome_template_path}")
    end

    verification_body = build_verification_body(store: store, id: id, intent_dir: intent_dir,
                                                 home: home, runner: runner, test_summary: test_summary)

    content = File.read(outcome_template_path).sub("# Outcome: <intent name>", "# Outcome: #{intent_name}")
    written = replace_section_body(content, "## Verification", [verification_body, "\n"])

    FileUtils.mkdir_p(intent_dir)
    File.write(target, written)
    ok_result(target)
  end

  def build_verification_body(store:, id:, intent_dir:, home:, runner:, test_summary:)
    repo = resolve_repo_dir(store: store, id: id, intent_dir: intent_dir, home: home, runner: runner)

    out = []
    if repo.nil?
      out << "Diffstat unavailable: no repo could be resolved for this intent\n"
    else
      base = detect_base_branch(repo, runner: runner)
      if base.nil?
        out << "Diffstat unavailable: no base branch could be detected (no origin/HEAD, main, or master)\n"
      else
        stat, err = diffstat(repo, base, runner: runner)
        if stat.nil?
          out << "Diffstat unavailable: #{err}\n"
        else
          out << "Diffstat against #{base}:\n"
          out << "```\n"
          out << stat
          out << "\n" unless stat.end_with?("\n")
          out << "```\n"
        end
      end
    end

    unless Bridge.blank?(test_summary)
      out << "\n"
      out << "Test summary from #{test_summary}:\n"
      out << "```\n"
      content = File.read(test_summary)
      out << content
      out << "\n" unless content.end_with?("\n")
      out << "```\n"
    end

    out.join
  end
end
