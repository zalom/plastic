# encoding: UTF-8
# frozen_string_literal: true

require "fileutils"
require "time"
require_relative "scaffold_intent"
require_relative "savepoint"
require_relative "intent_validator"
require_relative "worktree"

# BackfillIntent (intent 308) - write the four judgment documents of an intent from its
# record at intent end. The record is what an intent already carries by the time it
# closes: the intent file (`## Intent`, `### Decisions`, `## Insights`), checklist.md,
# and the diff on its own code worktree. Every section written here is a verbatim copy
# or a mechanical rendering of one of those; a section with no source keeps the
# template's own stub text, so nothing here invents prose. The one value that comes from
# the caller is outcome.md's `disposition:`, the closer's explicit assertion (spec D11).
#
# A target is backfilled only when it is missing or still the scaffold placeholder: the
# first line is the sentinel AND the body under it is nothing but the template
# (`edited_sentinel?`). A sentinel over hand-written lines counts as real. actions/ is
# backfilled as ACTION_1.md only when `Savepoint.has_real_action?` is false. A real file
# is never touched and there is no force flag. Every written file carries a marker
# comment on the line after its title, never the sentinel, so every reader treats it as
# real. A zero-byte spec.md or plan.md reads as real here exactly as it does in
# `Savepoint.stage_file_present?` (spec D1), so the doctor surfaces never disagree.
#
# Pure and dependency-injected like ScaffoldIntent: never exits, never reads ARGV or ENV
# (only the ambient Dir.home default), and takes the git seam as `runner:` so tests drive
# it in process with a fake runner.
module BackfillIntent
  module_function

  TARGETS = ["spec.md", "plan.md", "actions/ACTION_1.md", "outcome.md"].freeze
  TEMPLATED = ["spec.md", "plan.md", "outcome.md"].freeze
  MARKER_PREFIX = "<!-- backfilled from the record by end-intent on "
  ITEM_RE = /\A\s*- \[( |x|X)\] /.freeze
  TITLE_RE = /\A# /.freeze
  STUB_SECTIONS = {
    "## Goals" => "- ...\n", "## Non-Goals" => "- ...\n",
    "## Approach" => "(the chosen approach, in prose)\n",
    "## Alternatives Considered" => "- <alternative>: not chosen because ...\n",
  }.freeze

  def marker(now)
    "#{MARKER_PREFIX}#{now.utc.iso8601} -->"
  end

  # --- templates ---------------------------------------------------------------------

  # { "spec.md" => text, ... } for the templates that exist, else {}.
  def load_templates(templates_dir: nil, home: Dir.home)
    dir = templates_dir || ScaffoldIntent.resolve_templates_dir(home: home)
    return {} if dir.nil?

    TEMPLATED.each_with_object({}) do |name, acc|
      path = File.join(dir, name)
      acc[name] = File.read(path) if File.exist?(path)
    end
  end

  # --- target selection --------------------------------------------------------------

  # True iff `path` starts with the sentinel and its body carries a non-blank, non-title
  # line that the template for this file does not: someone wrote under the sentinel.
  # With no template known, any body line at all means edited.
  def edited_sentinel?(path, template_text, known_lines: [])
    lines = File.read(path).lines
    return false unless lines.first.to_s.chomp == Savepoint::PLACEHOLDER_SENTINEL

    body = lines.drop(1).map(&:strip).reject { |l| l.empty? || l.match?(TITLE_RE) }
    return body.any? if template_text.nil?

    known = template_text.lines.map(&:strip).reject(&:empty?) + known_lines.map(&:strip)
    (body - known).any?
  rescue StandardError
    true
  end

  # { targets: [rel], edited: [rel] }: the targets that need writing, and the sentinel
  # files that were left alone because their body was edited.
  def classify(intent_dir, templates: {}, known_lines: [])
    targets = []
    edited = []
    TEMPLATED.each do |rel|
      path = File.join(intent_dir, rel)
      next if Savepoint.stage_file_present?(path)

      if File.exist?(path) && edited_sentinel?(path, templates[rel], known_lines: known_lines)
        edited << rel
      else
        targets << rel
      end
    end
    unless Savepoint.has_real_action?(intent_dir)
      action = File.join(intent_dir, "actions", "ACTION_1.md")
      if File.exist?(action) && !Savepoint.stage_file_present?(action) && edited_sentinel?(action, nil)
        edited << "actions/ACTION_1.md"
      elsif !File.exist?(action) || !Savepoint.stage_file_present?(action)
        targets << "actions/ACTION_1.md"
      end
    end
    { targets: TARGETS & targets, edited: TARGETS & edited }
  end

  def targets_for(intent_dir, templates_dir: nil, home: Dir.home)
    classify(intent_dir, templates: load_templates(templates_dir: templates_dir, home: home))[:targets]
  end

  # --- reading the record (pure over file contents) ---------------------------------

  def strip_edges(lines)
    ScaffoldIntent.strip_blank_edges(lines)
  end

  def section_lines(text, heading)
    body = ScaffoldIntent.sections_from(text)[heading]
    return [] if body.nil?

    strip_edges(body.lines.map(&:rstrip)).reject { |l| l.start_with?("<!--") && l.end_with?("-->") }
  end

  # Every GFM checkbox item of checklist.md with its section and done flag. A continuation
  # line (indented, not an item, not a heading, not a table row) stays attached to the item
  # above it so a wrapped item round-trips verbatim.
  def checklist_items(text)
    items = []
    section = nil
    text.each_line do |raw|
      line = raw.rstrip
      if line.start_with?("## ")
        section = line
      elsif (m = ITEM_RE.match(line))
        items << { line: line, done: m[1] != " ", section: section }
      elsif items.any? && line.start_with?("  ") && !line.start_with?("  |") && section == items.last[:section]
        items.last[:line] = "#{items.last[:line]}\n#{line}"
      end
    end
    items
  end

  def session_log_lines(text)
    section_lines(text, "## Session Log").select { |l| l.start_with?("|") }
  end

  # [record, nil] or [nil, message] when the intent file is missing. `record[:notes]`
  # names every source that was absent; an absent source never stops the write.
  def read_record(intent_dir)
    intent_file = Savepoint.intent_file(intent_dir)
    return [nil, "the intent file is missing at #{intent_file}"] unless File.exist?(intent_file)

    content = File.read(intent_file)
    fm = IntentValidator.parse_frontmatter_text(content)
    name = fm.is_a?(Hash) ? fm["intent"].to_s.strip : ""
    notes = []
    if name.empty?
      name = File.basename(intent_dir)
      notes << "the intent file has no frontmatter intent name; the directory name stands in"
    end
    decisions, = ScaffoldIntent.extract_decisions(content)
    notes << "the intent file has no ### Decisions list; spec.md says so" if decisions.nil?

    checklist = File.join(intent_dir, "checklist.md")
    checklist_text = ""
    if Savepoint.stage_file_present?(checklist)
      checklist_text = File.read(checklist)
    else
      notes << "checklist.md is missing or still a placeholder; the item sections say so"
    end

    [{
      name: name,
      intent_body: section_lines(content, "## Intent"),
      decisions: decisions,
      insights: section_lines(content, "## Insights"),
      items: checklist_items(checklist_text),
      session_log: session_log_lines(checklist_text),
      notes: notes,
    }, nil]
  end

  # --- rendering (pure) ---------------------------------------------------------------

  def block(lines, empty)
    lines.empty? ? "#{empty}\n" : "#{lines.join("\n")}\n"
  end

  def template_stub(template_text, heading)
    body = template_text && ScaffoldIntent.sections_from(template_text)[heading]
    body = STUB_SECTIONS.fetch(heading, "") if body.nil? || body.strip.empty?
    "#{body.rstrip}\n"
  end

  def render(record, disposition:, summary:, verification:, now:, templates: {})
    mark = marker(now)
    items = record[:items].map { |i| i[:line] }
    done = record[:items].select { |i| i[:done] }.map { |i| i[:line] }
    open = record[:items].reject { |i| i[:done] }.map { |i| i[:line] }
    decisions = record[:decisions].nil? ? "(none recorded in the intent file)\n" : record[:decisions]
    decisions += "\n" unless decisions.end_with?("\n")

    spec = +"# Spec: #{record[:name]}\n#{mark}\n\n"
    spec << "## Problem\n#{block(record[:intent_body], '(not recorded in the intent file)')}\n"
    STUB_SECTIONS.each_key { |h| spec << "#{h}\n#{template_stub(templates['spec.md'], h)}\n" }
    spec << "## Decisions\n#{decisions}\n"
    spec << "## Acceptance Criteria\n#{block(items, '(no checklist items recorded)')}\n"
    spec << "## Open Questions\nNone\n"

    plan = +"# Plan: #{record[:name]}\n#{mark}\n\n"
    plan << "## Goal\n#{record[:name]}\n\n"
    plan << "## Steps\n#{block(items, '(no checklist items recorded)')}\n"
    plan << "## Notes\n#{block(record[:insights], '(no insights recorded)')}"

    action = +"# ACTION_1: #{record[:name]}\n#{mark}\n\n"
    action << "## Items\n#{block(items, '(no checklist items recorded)')}\n"
    action << "## Session Log\n#{block(record[:session_log], '(none)')}"

    summary_text = summary.to_s.strip
    summary_text = "(no summary given at close)" if summary_text.empty?
    outcome = +"---\ndisposition: #{disposition}\n---\n# Outcome: #{record[:name]}\n#{mark}\n\n"
    outcome << "## Summary\n#{summary_text}\n\n"
    outcome << "## Delivered\n#{block(done, '(no completed checklist items recorded)')}\n"
    outcome << "## Verification\n#{verification.to_s.strip.empty? ? "(no diff available)\n" : verification}\n"
    outcome << "## Follow-ups\n#{block(open, 'None')}"

    { "spec.md" => spec, "plan.md" => plan, "actions/ACTION_1.md" => action, "outcome.md" => outcome }
  end

  # --- the diff, from this intent's own code worktree only -----------------------------

  # The provisioned code worktree for this intent when it exists on disk, else nil. Never
  # the current directory's repo: a store-only intent closed from an unrelated checkout
  # must not report that checkout's diff.
  def worktree_dir(store:, id:, intent_dir:, home: Dir.home)
    wt_home = Worktree.home_from_store(store) || home
    slug = Worktree.slug_for_store(store, home: wt_home)
    return nil if slug.nil?

    intent_slug = File.basename(intent_dir).split("--", 2).last
    code = Worktree.paths(slug: slug, intent_id: id, intent_slug: intent_slug, home: wt_home)["code"]
    code && Dir.exist?(code) ? code : nil
  end

  def verification_body(store:, id:, intent_dir:, home:, runner:)
    repo = worktree_dir(store: store, id: id, intent_dir: intent_dir, home: home)
    return "Diffstat unavailable: this intent provisioned no code worktree\n" if repo.nil?

    base = ScaffoldIntent.detect_base_branch(repo, runner: runner)
    return "Diffstat unavailable: no base branch could be detected (no origin/HEAD, main, or master)\n" if base.nil?

    stat, err = ScaffoldIntent.diffstat(repo, base, runner: runner)
    return "Diffstat unavailable: #{err}\n" if stat.nil?

    "Diffstat against #{base}:\n```\n#{stat}#{stat.end_with?("\n") ? "" : "\n"}```\n"
  rescue StandardError => e
    "Diffstat unavailable: #{e.message}\n"
  end

  # --- writing, atomic inside the intent dir -------------------------------------------

  def write_atomic(intent_dir, relative, content)
    target = File.join(intent_dir, relative)
    FileUtils.mkdir_p(File.dirname(target))
    tmp = File.join(File.dirname(target), ".filing-#{File.basename(target)}")
    File.write(tmp, content)
    File.rename(tmp, target)
    target
  end

  # A `.filing-*` left by an earlier crash would otherwise ride into the store commit.
  def remove_stale_filing(intent_dir)
    Dir.glob([File.join(intent_dir, ".filing-*"), File.join(intent_dir, "actions", ".filing-*")]).each do |f|
      File.delete(f) if File.file?(f)
    end
  end

  # Returns { written: [rel], skipped: [rel], notes: [String] }. `skipped` lists the
  # targets that already carry real content (an edited sentinel among them, named in
  # `notes`). `notes` names every absent source; an absent source never stops the write.
  # One savepoint line, `Exec  backfilled <list>`, records the fact (idempotent per list).
  def run(intent_dir:, store:, id:, disposition:, summary: nil, home: Dir.home,
          runner: Worktree::ShellRunner.new, templates_dir: nil, now: Time.now)
    result = { written: [], skipped: [], notes: [] }
    remove_stale_filing(intent_dir)

    templates = load_templates(templates_dir: templates_dir, home: home)
    record, err = read_record(intent_dir)
    if record.nil?
      result[:notes] << err
      result[:skipped] = TARGETS - classify(intent_dir, templates: templates)[:targets]
      return result
    end

    classified = classify(intent_dir, templates: templates, known_lines: [record[:name]])
    targets = classified[:targets]
    result[:skipped] = TARGETS - targets
    classified[:edited].each do |rel|
      result[:notes] << "#{rel} carries a sentinel over hand-written content; left untouched"
    end
    result[:notes].concat(record[:notes])
    return result if targets.empty?

    verification = nil
    if targets.include?("outcome.md")
      verification = verification_body(store: store, id: id, intent_dir: intent_dir, home: home, runner: runner)
    end
    docs = render(record, disposition: disposition, summary: summary, verification: verification,
                  now: now, templates: templates)
    targets.each do |rel|
      write_atomic(intent_dir, rel, docs.fetch(rel))
      result[:written] << rel
    end
    Savepoint.append_savepoint_line(intent_dir, "Exec", "backfilled #{result[:written].join(', ')}", now)
    result
  end
end
