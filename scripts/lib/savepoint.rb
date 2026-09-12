#!/usr/bin/env ruby
# encoding: UTF-8
# frozen_string_literal: true

# Savepoint: the intent-directory savepoint ledger and the stage derivation it
# rests on (intent 303, split out of bridge.rb). Everything here is derived from
# the files on disk inside one intent directory: which lifecycle files are real
# (not the placeholder sentinel), which stage that makes, and the append-only
# savepoint.md ledger that records each milestone. No session, no bridge, no
# lock: a caller that only wants to append a ledger line or ask "which stage is
# this intent at" loads this file and nothing else. bridge.rb (the session
# pointer, arm and disarm, lock repair) requires this file; this file never
# requires the bridge.
require "fileutils"
require "time" # Time#iso8601 for the ledger timestamps

module Savepoint
  # Placeholder sentinel (intent 60b). A scaffolded lifecycle file
  # (spec.md/plan.md/checklist.md/outcome.md) carries this exact string as its
  # first line until an agent fills the file and deletes the sentinel. The
  # sentinel is the "stage not reached yet" marker, so stage detection treats a
  # sentinel-marked file as absent (see stage_file_present?). The intent file
  # (<id>--<slug>.md) is never sentineled; it is born complete.
  PLACEHOLDER_SENTINEL = "<!-- plastic:placeholder -->"

  # --- Node-graph transition subject vocabulary (intent 335, spec D17) -------
  #
  # Owned HERE, not on NodeLedger, because test/savepoint_split_test.rb:57 pins
  # savepoint.rb to loading no other project file: NodeLedger requires this
  # file and reuses these three names rather than duplicating them, so the
  # dependency runs one way only. Intent 334 (G1) mints node ids and must
  # agree with NODE_SUBJECT_RE: it is the single seam for the node id shape.

  # The literal subject token for an intent-scope transition line ("Intent
  # needs_decision question=..."), as opposed to a node-scope line.
  INTENT_SUBJECT = "Intent"

  # A node id: one or two lowercase letters (the node's kind prefix, e.g. "n"
  # for work, "v" for verify) followed by digits.
  NODE_SUBJECT_RE = /\A[a-z]{1,2}\d+\z/.freeze

  # True iff a raw savepoint ledger line's subject (field 2, split on
  # /\s{2,}/) is a transition candidate: the literal Intent token or a node
  # id. A stage line ("How  checklist.md created") or a Lock takeover audit
  # line never matches, by construction (spec Acceptance Criteria: "no stage
  # token this tree writes collides with Intent or with the node id
  # pattern").
  def self.transition_candidate?(line)
    parts = line.to_s.split(/\s{2,}/)
    return false unless parts.length >= 2

    subject = parts[1]
    subject == INTENT_SUBJECT || subject.match?(NODE_SUBJECT_RE)
  end

  def self.intent_file(intent_dir)
    dir_name = File.basename(intent_dir)
    "#{intent_dir}/#{dir_name}.md"
  end

  # Walk up from file_path; return the first ancestor that looks like an intent
  # directory (`.../store/<id>--<slug>`), else nil. Used to derive the savepoint
  # target without needing a bridge. The input is always a file inside the intent
  # dir (never the dir itself), so the walk-up starts at its parent.
  def self.intent_dir_for(file_path)
    dir = File.expand_path(file_path)
    loop do
      parent = File.dirname(dir)
      break if parent == dir # reached filesystem root
      dir = parent
      return dir if dir.match?(%r{/store/[^/]+--[^/]+\z})
    end
    nil
  end

  # True iff a lifecycle file is PRESENT AND REAL: it exists and its first line is
  # not the placeholder sentinel. Reads only the file head (never the whole file)
  # so the dashboard stays fast across many intents. Exact first-line match only,
  # so a real file that merely contains an HTML comment later is unaffected, and a
  # partially-edited sentinel reads as real rather than sticking as a placeholder.
  def self.stage_file_present?(path)
    return false unless File.exist?(path)
    first = File.open(path, &:gets)
    return true if first.nil? # empty file: present, not a sentinel
    first.chomp != PLACEHOLDER_SENTINEL
  rescue StandardError
    File.exist?(path)
  end

  # True iff DIR_NAME (actions/ or nodes/) holds AT LEAST ONE real *.md file: non-empty,
  # first line not the placeholder sentinel. A `.gitkeep` (no .md extension) never counts.
  # Pure and side-effect-free; fail-open (a missing dir globs to nothing, never raises).
  def self.has_real_files_in?(dir_name, intent_dir)
    Dir.glob("#{intent_dir}/#{dir_name}/*.md").any? do |f|
      File.file?(f) && File.size(f) > 0 && stage_file_present?(f)
    end
  rescue StandardError
    false
  end

  # True iff the intent has at least one real action file, whether delivered as
  # legacy actions/*.md or as a node graph's nodes/*.md (intent 334, G1, D10r):
  # an intent delivered as nodes is exactly as real as one delivered as
  # actions, so doctor and the exec-stage gate never report a backfill gap on
  # a fully delivered node-graph intent. Checks actions/ first (the common
  # path today), falling through to nodes/ only when actions/ has nothing.
  def self.has_real_action?(intent_dir)
    has_real_files_in?("actions", intent_dir) || has_real_files_in?("nodes", intent_dir)
  rescue StandardError
    false
  end

  # Intent 336 (G3, D13): a real graph.md is 327 D41's replacement for
  # plan.md/checklist.md on the common path, so a node-shaped intent is
  # judged on graph.md and nodes/ alone, whether or not spec.md is real - the
  # graph IS the spec under D41. Checked using only this file's own
  # primitives (stage_file_present?, has_real_files_in?), because
  # test/savepoint_split_test.rb pins this file to loading no other project
  # file and no YAML: GraphFile/NodeFile/ReadySet are never required here. An
  # intent with no real graph.md (or a sentinel-placeholder one,
  # stage_file_present? already reads that as absent) derives exactly what it
  # derived before this intent.
  def self.derive_stage(intent_dir)
    return "done" if stage_file_present?("#{intent_dir}/outcome.md")

    if stage_file_present?("#{intent_dir}/graph.md")
      return "exec" if has_real_files_in?("nodes", intent_dir)
      return "how"
    end

    if stage_file_present?("#{intent_dir}/plan.md") &&
       has_real_action?(intent_dir) &&
       stage_file_present?("#{intent_dir}/checklist.md")
      return "exec"
    end
    return "how" if stage_file_present?("#{intent_dir}/spec.md")
    return "why" if File.exist?(intent_file(intent_dir))
    "what"
  end

  def self.has_files(intent_dir)
    files = []
    ifile = File.basename(intent_file(intent_dir))
    files << ifile if File.exist?("#{intent_dir}/#{ifile}")
    ["spec.md", "graph.md", "plan.md", "checklist.md", "outcome.md"].each do |f|
      files << f if stage_file_present?("#{intent_dir}/#{f}")
    end
    # Name the directory that actually exists (review B3): a nodes-only intent
    # must never claim the literal "actions/" artifact it does not have.
    # Checks actions/ first, matching D15r's read order.
    if has_real_files_in?("actions", intent_dir)
      files << "actions/"
    elsif has_real_files_in?("nodes", intent_dir)
      files << "nodes/"
    end
    files
  end

  def self.missing_for_stage(stage, intent_dir = nil)
    ifile = intent_dir ? File.basename(intent_file(intent_dir)) : "intent.md"
    # A How-stage intent that already started a nodes/ directory is named
    # accordingly, so the next-step hint never tells a node-graph intent to
    # go make an actions/ directory it will never use (review B3). Mirrors
    # has_real_files_in?'s actions-first order and its real-file requirement
    # (post-execution review, non-blocking 4): an intent carrying real files
    # in both directories, or a real actions/ file beside an empty or
    # .gitkeep-only nodes/, is named actions/, never nodes/.
    action_label = if intent_dir && has_real_files_in?("actions", intent_dir)
      "actions/"
    elsif intent_dir && has_real_files_in?("nodes", intent_dir)
      "nodes/"
    else
      "actions/"
    end
    case stage
    when "what" then [ifile]
    when "why" then ["spec.md"]
    when "how"
      # A node-shaped How intent (a real graph.md already) is named after its
      # own two artifacts, never the three D41 removed from its path (review
      # B3, extended by 336 D13): checked via stage_file_present? alone, the
      # same primitive derive_stage itself uses.
      if intent_dir && stage_file_present?("#{intent_dir}/graph.md")
        ["graph.md", "nodes/"]
      else
        ["plan.md", action_label, "checklist.md"]
      end
    when "exec" then ["outcome.md"]
    else []
    end
  end

  # --- Cycle-step savepoint ledger (intent 34) ------------------------------
  #
  # savepoint.md is a deterministic, append-only, one-line-per-milestone ledger
  # (newest at the bottom). It is sugar on top of the conventions: derived from
  # files-on-disk, rebuildable, never a source of truth. Milestones are
  # file-event boundaries only; action/resource files record nothing.

  SAVEPOINT_FILE = "savepoint.md"

  # Map a written filename to [stage_label, milestone_text], or nil if the file
  # is not a lifecycle milestone.
  def self.savepoint_milestone(intent_dir, basename)
    return ["What", basename] if basename == File.basename(intent_file(intent_dir))

    case basename
    when "spec.md"      then ["Why", "spec.md created"]
    when "plan.md"      then ["How", "plan.md created"]
    when "checklist.md" then ["How", "checklist.md created"]
    when "outcome.md"   then ["Exec", "outcome.md created"]
    end
  end

  # Milestones already recorded in the ledger (field 3 of each line).
  def self.savepoint_recorded_milestones(intent_dir)
    f = File.join(intent_dir, SAVEPOINT_FILE)
    return [] unless File.exist?(f)
    File.read(f).each_line.map do |line|
      parts = line.strip.split(/\s{2,}/)
      parts.length >= 3 ? parts[2] : nil
    end.compact
  end

  # (stage, milestone) pairs already recorded in the ledger. The pair (not the
  # milestone text alone) is the dedup key, because state-from-ledger lines like
  # `Why  started` and `How  started` share the milestone text "started" while
  # being distinct events (intent 81).
  def self.savepoint_recorded_pairs(intent_dir)
    f = File.join(intent_dir, SAVEPOINT_FILE)
    return [] unless File.exist?(f)
    File.read(f).each_line.filter_map do |line|
      parts = line.strip.split(/\s{2,}/)
      parts.length >= 3 ? [parts[1], parts[2]] : nil
    end
  end

  # Append one ledger line for (stage, milestone) unless that pair is already
  # recorded. The single append primitive shared by every line class. Returns
  # true when a line was written, false when it was a no-op.
  def self.append_savepoint_line(intent_dir, stage, milestone, now)
    return false if savepoint_recorded_pairs(intent_dir).include?([stage, milestone])
    line = "#{now.utc.iso8601}  #{stage}  #{milestone}\n"
    File.open(File.join(intent_dir, SAVEPOINT_FILE), "a") { |io| io.write(line) }
    true
  end

  # Append the artifact-landing milestone for file_path if (and only if) it is a
  # milestone not already recorded. Returns true when a line was written.
  def self.append_savepoint(intent_dir, file_path, now: Time.now)
    basename = File.basename(file_path)
    stage, milestone = savepoint_milestone(intent_dir, basename)
    return false unless milestone
    # A sentinel-marked lifecycle file logs NO milestone (the stage is not real
    # yet). The intent file is never sentineled, so it still logs its What line.
    return false unless stage_file_present?(File.join(intent_dir, basename))

    append_savepoint_line(intent_dir, stage, milestone, now)
  end

  # --- State-from-ledger: pre-stage, exec-start, and terminal lines (81) ------
  #
  # On top of intent 34's artifact-landing milestones, the ledger gains:
  #   - `started` lines, one per cycle stage entry (pre-stage, written by the
  #     PreToolUse savepoint hook the moment a stage's artifact is first written);
  #   - an `Exec  started` companion emitted when checklist.md lands;
  #   - a terminal `Done  delivered|abandoned` line written by the completion path.
  # None of these are derivable from files on disk, so they are deliberately NOT
  # part of savepoint_milestone and are never regenerated by rebuild_savepoint:
  # a rebuilt ledger is the file-landing skeleton, the live ledger is richer.

  # Map a written filename to the [stage, "started"] pre-stage milestone, or nil.
  # spec.md => entering Why, plan.md => entering How. checklist.md/outcome.md do
  # not open a stage (checklist's Exec-start is the append_exec_started companion).
  def self.savepoint_started_milestone(basename)
    case basename
    when "spec.md" then ["Why", "started"]
    when "plan.md" then ["How", "started"]
    end
  end

  # Append the pre-stage `started` line for file_path, iff: the basename opens a
  # stage, the stage is genuinely starting (its artifact is not yet a REAL file,
  # so a sentinel placeholder still counts as "starting"), and the pair is not
  # already recorded. Returns true when a line was written.
  def self.append_started_savepoint(intent_dir, file_path, now: Time.now)
    basename = File.basename(file_path)
    stage, milestone = savepoint_started_milestone(basename)
    return false unless milestone
    return false if stage_file_present?(File.join(intent_dir, basename))

    append_savepoint_line(intent_dir, stage, milestone, now)
  end

  # Append the `Exec  started` companion (emitted when checklist.md lands, in the
  # same PostToolUse event as the `How  checklist.md created` line). Idempotent.
  def self.append_exec_started(intent_dir, now: Time.now)
    append_savepoint_line(intent_dir, "Exec", "started", now)
  end

  # Append a `Review` line: one per plan-review or post-execution-review verdict
  # (intent 317, D5/D17). Same shape as every other line, through the shared
  # append_savepoint_line primitive, so dedup and the timestamp format never
  # drift from the one line-writer every other kind already uses.
  def self.append_review_savepoint(intent_dir, text, now: Time.now)
    append_savepoint_line(intent_dir, "Review", text, now)
  end

  # Append a `Commit` line: one per commit landing during Exec (intent 317,
  # D5/D17). Same primitive as append_review_savepoint above.
  def self.append_commit_savepoint(intent_dir, text, now: Time.now)
    append_savepoint_line(intent_dir, "Commit", text, now)
  end

  # The day the Report kind (below) shipped. `doctor`'s intent_reports_printed_check reads
  # this so it never re-litigates a ledger recorded before the kind existed (intent 331f, R6).
  REPORT_KIND_SINCE = "2026-09-05"

  # Append a `Report` line: one per report screen printed (intent 331f, D2/D3). Same primitive
  # as append_review_savepoint/append_commit_savepoint above, so the line shape, dedup, and
  # timestamp format never drift. `savepoint_milestone` maps FILENAMES only, so a Report line
  # is never mistaken for a file-landing lifecycle line by construction.
  def self.append_report_savepoint(intent_dir, text, now: Time.now)
    append_savepoint_line(intent_dir, "Report", text, now)
  end

  TERMINAL_DISPOSITIONS = %w[delivered abandoned].freeze

  # Append the terminal bookend `Done  delivered|abandoned`, written by the
  # completion path when an intent transfers to INDEX's Completed/Abandoned
  # section. Idempotent per disposition. Raises on an unknown disposition.
  def self.append_terminal_savepoint(intent_dir, disposition, now: Time.now)
    unless TERMINAL_DISPOSITIONS.include?(disposition)
      raise ArgumentError,
            "disposition must be one of #{TERMINAL_DISPOSITIONS.join(', ')}, got #{disposition.inspect}"
    end

    append_savepoint_line(intent_dir, "Done", disposition, now)
  end

  # Reconstruct the ledger from files on disk (timestamps from mtimes), in
  # stage order, overwriting savepoint.md. Returns the number of lines written.
  # A Plastic 1.x ledger may carry a `Tier  <value>` line after the spec.md
  # milestone (removed in 2.0, intent 304); a rebuild drops it, and the phantom
  # detector ignores it, so a 1.x store reads clean.
  #
  # Every transition line (intent 335, spec D13) is preserved VERBATIM, in its
  # original relative order, after the reconstructed stage skeleton. It is
  # never dropped and never refused: a transition line's evidence fields
  # (`holder=`, `expires=`, `gates=`, ...) have no file-mtime analog to
  # reconstruct from, so refusing instead of preserving would make this method
  # destroy the graph's only status on every intent that carries one. Relative
  # order BETWEEN a stage line and a transition line is not preserved (safe:
  # status is computed per subject, and the two families share no subject);
  # relative order WITHIN the transition lines is preserved, which is what
  # "last line per subject in file order" depends on.
  def self.rebuild_savepoint(intent_dir)
    ordered = [
      File.basename(intent_file(intent_dir)),
      "spec.md", "plan.md", "checklist.md", "outcome.md",
    ]
    lines = ordered.flat_map do |basename|
      path = File.join(intent_dir, basename)
      next [] unless stage_file_present?(path)
      stage, milestone = savepoint_milestone(intent_dir, basename)
      next [] unless milestone
      stamp = File.mtime(path).utc.iso8601
      ["#{stamp}  #{stage}  #{milestone}\n"]
    end

    savepoint_path = File.join(intent_dir, SAVEPOINT_FILE)
    if File.exist?(savepoint_path)
      # #scrub before scanning (post-execution review row 7.8), the same way
      # NodeLedger.entries does (matrix 2.44): a stray non-UTF-8 byte anywhere
      # in the ledger must not raise out of the one repair tool three doctor
      # fix hints and maintenance-run --tool rebuild-savepoint point at.
      transition_lines = File.read(savepoint_path).scrub.each_line.select { |raw| transition_candidate?(raw) }
      lines += transition_lines.map { |raw| raw.end_with?("\n") ? raw : "#{raw}\n" }
    end

    File.write(savepoint_path, lines.join)
    lines.length
  end

  # --- Phantom-line detection (intent 134) ------------------------------------
  #
  # A companion to the ledger, not a new writer: pure, disk-only, hermetic (no bridge or
  # session resolution, no writes), matching intent 52's savepoint-decoupling precedent. Under
  # a gate-routing misfire (bug 131) or an out-of-band merge (124a's precedent), a ledger line
  # can go stale or duplicate without the file evidence agreeing. This detects, never repairs;
  # repair is `rebuild_savepoint` (live intents) or the 124a manual Done-bookend recipe
  # (terminal intents, human-granted only).

  # (stage, milestone) -> basename, for every file-landing milestone this intent_dir could have
  # produced (the intent file plus the four lifecycle artifacts). Reuses savepoint_milestone so
  # the mapping never drifts from the one the writer itself uses.
  def self.savepoint_file_landing_pairs(intent_dir)
    basenames = [File.basename(intent_file(intent_dir)), "spec.md", "plan.md", "checklist.md", "outcome.md"]
    basenames.each_with_object({}) do |basename, map|
      pair = savepoint_milestone(intent_dir, basename)
      map[pair] = basename if pair
    end
  end

  # A `started` state line's real prerequisite is the PRECEDING stage's artifact, not its own
  # (a `started` line legitimately fires before its own stage's file is real by design). `Exec
  # started` additionally requires plan.md, since Exec cannot start before How produced it too.
  SAVEPOINT_STATE_PREREQUISITES = {
    ["How", "started"] => ["spec.md"],
    ["Exec", "started"] => ["plan.md", "checklist.md"],
  }.freeze

  # Raw (stripped) ledger lines whose disk evidence contradicts them, each paired with a short
  # reason: [line, reason]. Three phantom classes (D5):
  #   - a file-landing milestone whose file is absent or still a sentinel placeholder;
  #   - a duplicate (stage, milestone) pair (the later occurrence is the phantom);
  #   - a state line (`How started` / `Exec started`) whose stage prerequisites are absent.
  # A clean ledger, or an absent one, returns [].
  def self.savepoint_phantom_lines(intent_dir)
    path = File.join(intent_dir, SAVEPOINT_FILE)
    return [] unless File.exist?(path)

    landing = savepoint_file_landing_pairs(intent_dir)
    seen = []
    phantoms = []

    File.read(path).each_line do |raw|
      line = raw.strip
      next if line.empty?
      # A transition line (intent 335) is never a stage phantom candidate: its
      # own repeated-line semantics (dedup-free by design, spec D11) are
      # NodeLedger's concern, not this detector's.
      next if transition_candidate?(line)
      parts = line.split(/\s{2,}/)
      next if parts.length < 3
      pair = [parts[1], parts[2]]

      if seen.include?(pair)
        phantoms << [line, "duplicate (stage, milestone) pair"]
        next
      end
      seen << pair

      if (basename = landing[pair]) && !stage_file_present?(File.join(intent_dir, basename))
        phantoms << [line, "milestone file absent or still a sentinel placeholder"]
        next
      end

      prereqs = SAVEPOINT_STATE_PREREQUISITES[pair]
      if prereqs && prereqs.any? { |b| !stage_file_present?(File.join(intent_dir, b)) }
        phantoms << [line, "state line prerequisite absent on disk"]
      end
    end

    phantoms
  end
end
