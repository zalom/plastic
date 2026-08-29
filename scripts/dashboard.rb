#!/usr/bin/env ruby
# encoding: UTF-8
# frozen_string_literal: true

# Plastic dashboard — deterministic, template-driven work cockpit.
#
# Parses the intent store(s), classifies every actionable intent on a Value x Effort
# matrix (Eisenhower-style), and renders a uniform view that tells a human AND an agent
# what to work on next and how to conduct it. The LLM is never in the rendering path:
# same store state -> byte-identical output.
#
# Usage:
#   ruby dashboard.rb [continue|project <slug>|all] [--json]
#   ruby dashboard.rb [continue|project <slug>] --data [--limit-active N] [--limit-next N] [--all]
#   ruby dashboard.rb [continue|project <slug>] --plain
# Default mode: continue.
#
# Env overrides (for deterministic tests):
#   PLASTIC_HOME      — root of the Plastic store (default ~/.plastic)
#   DASHBOARD_TODAY   — YYYY-MM-DD used for the header + staleness math
#
# Read-only. Never modifies files.

require "json"
require "yaml"
require "date"
require_relative "doctor"
require_relative "lib/savepoint"
require_relative "lib/lock"

PLASTIC_HOME = ENV.fetch("PLASTIC_HOME") { File.join(Dir.home, ".plastic") }

def today
  s = ENV["DASHBOARD_TODAY"]
  s && !s.empty? ? Date.parse(s) : Date.today
end

# A generic "about a month" threshold, not tuned to any one store's item count.
# Deliberately independent from plastic-intent-continuing's separate stale_threshold_days
# config: that one is a proactive boot-time triage nudge, this is a board annotation.
# Unifying the two is a follow-up, not this intent.
STALE_DAYS = 30

# ---------------------------------------------------------------------------
# Parsing — reuses the conventions in scripts/doctor.rb
# ---------------------------------------------------------------------------

def parse_frontmatter(path)
  return nil unless File.exist?(path)
  content = File.read(path)
  return nil unless content.start_with?("---")
  parts = content.split("---", 3)
  return nil if parts.length < 3
  YAML.safe_load(parts[1], permitted_classes: [Date, Time]) || {}
rescue StandardError
  nil
end

# Returns the set of intent ids listed under a given INDEX.md section.
def index_section_ids(index_path, header)
  return [] unless File.exist?(index_path)
  body = File.read(index_path)
  seg = body[/^#{Regexp.escape(header)}\s*\n(.*?)(?=^## |\z)/m, 1]
  return [] unless seg
  seg.scan(/^- \[([^\]\s]+)/).flatten
end

# Bug found at intent 202's gate review: the date used to be anchored to the END of the
# line, which was true of old INDEX.md entries but stopped being true the moment
# `scripts/end-intent --index-note "..."` started writing the date FOLLOWED BY the note
# text (that has been the documented completion path for every completion since it
# shipped). Anchored-to-end-of-line silently missed the date on every noted entry.
# Fixed by anchoring to the position right after the markdown link's closing paren
# instead, with no end-of-line requirement, so trailing note prose is irrelevant. The
# separator there may be a real em dash (U+2014, INDEX.md's normal on-write convention,
# built from the codepoint so this source line stays em-dash free) or a plain hyphen
# (end-intent's own Bridge.index_entry_match accepts either on read). Because regex
# alternation is leftmost-first, this only ever matches the date immediately after the
# link. It never continues scanning into the note prose, so a second date mentioned
# later in a note's free text cannot be mistaken for the completion date.
COMPLETION_DATE_RE = /^- \[([^\]\s]+).*?\)\s*[\u2014-]\s*(\d{4}-\d{2}-\d{2})\b/

# Map of intent id -> completion date string, parsed from the "## Completed" section
# (lines like "- [12 (em dash) title](link) (em dash) 2026-06-10 optional note text").
# Deterministic, content-derived. Observability: a populated "## Completed" section that
# yields not one single dated entry is a parser regression, not a legitimately empty
# result, so it is surfaced with a stderr warning rather than rotting invisibly (the same
# silent-failure class intent 202's gate review caught this file already committing).
def completion_dates(index_path)
  return {} unless File.exist?(index_path)
  body = File.read(index_path)
  seg = body[/^## Completed\s*\n(.*?)(?=^## |\z)/m, 1] || ""
  entry_count = seg.scan(/^- \[/).size
  dates = seg.scan(COMPLETION_DATE_RE).to_h
  if entry_count.positive? && dates.empty?
    warn "dashboard: completion_dates parsed 0/#{entry_count} dates from the " \
         "\"## Completed\" section of #{index_path}; treat this as a parser regression, " \
         "not a genuinely undated store."
  end
  dates
end

# All stores: global + every registered project. -> [{scope, store, index}]
def stores
  list = []
  global = File.join(PLASTIC_HOME, "store")
  list << { scope: "global", store: global, index: File.join(PLASTIC_HOME, "INDEX.md") } if File.directory?(global)
  projects_root = File.join(PLASTIC_HOME, "projects")
  if File.directory?(projects_root)
    Dir.children(projects_root).sort.each do |proj|
      store = File.join(projects_root, proj, "store")
      next unless File.directory?(store)
      list << { scope: "project:#{proj}", store: store, index: File.join(projects_root, proj, "INDEX.md") }
    end
  end
  list
end

def intent_dirs(store)
  Dir.children(store).reject { |e| e.start_with?(".") }
     .select { |e| File.directory?(File.join(store, e)) }
     .sort
end

# Last-accessed timestamp: the timestamp of the last ISO8601 line in the
# deterministic savepoint ledger (intent 34); falls back to the created date.
ISO8601_RE = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\b/

def last_accessed_at(dir, created)
  sp = File.join(dir, "savepoint.md")
  if File.exist?(sp)
    File.readlines(sp).reverse_each do |line|
      m = line.strip.match(ISO8601_RE)
      return m[0] if m
    end
  end
  return "#{created}T00:00:00Z" if created && !created.empty?
  ""
end

# D3 fix (intent 202 gate review): the actual moment an intent finished, distinct from
# completion_dates' day-granularity date. Reads savepoint.md bottom-up like
# last_accessed_at above, but matches on the stage token specifically ("Done") instead of
# taking whatever the last line says, so a ledger touched again after Done (which would
# violate the completed-intents-immutable convention) still reports the true Done moment
# rather than whatever ran later. Returns nil when there is no savepoint or no Done line,
# so callers get an honest "no signal" instead of a fabricated time.
def done_timestamp(dir)
  sp = File.join(dir, "savepoint.md")
  return nil unless File.exist?(sp)
  File.readlines(sp).reverse_each do |line|
    stripped = line.strip
    next if stripped.empty?
    fields = stripped.split(/\s+/)
    next unless fields[1] == "Done"
    m = fields[0].match(ISO8601_RE)
    return m[0] if m
  end
  nil
rescue StandardError
  nil
end

# True iff the savepoint ledger's last non-blank line shows real post-birth
# activity, not just the one-line birth stamp every intent gets at creation
# (scripts/new-intent's Savepoint.append_savepoint call, stage "What"). Reads the
# last line, extracts the stage token (second whitespace-separated field, same
# ledger shape last_accessed_at already parses), and treats any stage other
# than "What" as progress. Returns false when the file is missing/empty.
def savepoint_shows_progress?(path)
  return false unless File.exist?(path)
  last_line = nil
  File.readlines(path).reverse_each do |line|
    stripped = line.strip
    next if stripped.empty?
    last_line = stripped
    break
  end
  return false unless last_line
  stage = last_line.split(/\s+/)[1]
  !stage.nil? && stage != "What"
end

# Parse one intent directory into a raw record.
def parse_intent(store_info, dir_name, status_index)
  dir = File.join(store_info[:store], dir_name)
  md = File.join(dir, "#{dir_name}.md")
  fm = parse_frontmatter(md)
  return nil unless fm && fm["id"]

  id = fm["id"].to_s
  # Sentinel-aware presence for lifecycle files (intent 60b): a scaffolded
  # placeholder spec/plan/checklist/outcome reads as absent, so a freshly
  # scaffolded intent reports What/Why and is never marked completed/advanced.
  real = ->(f) { Savepoint.stage_file_present?(File.join(dir, f)) }
  body = File.exist?(md) ? File.read(md) : ""

  status =
    if real.("outcome.md") then "completed"
    elsif status_index[:active].include?(id) then "active"
    elsif status_index[:abandoned].include?(id) then "abandoned"
    elsif status_index[:completed].include?(id) then "completed"
    else "future"
    end

  {
    id: id,
    scope: store_info[:scope],
    intent: (fm["intent"] || "").to_s.strip,
    author: (fm["author"] || "").to_s,
    tags: fm["tags"] || [],
    sources: (fm["sources"] || []).map(&:to_s),
    chain: (fm["chain"] || []).map(&:to_s),
    created: (fm["created"].to_s rescue ""),
    value_field: fm["value"] && fm["value"].to_s,
    status: status,
    spec: real.("spec.md"),
    plan: real.("plan.md"),
    checklist: real.("checklist.md"),
    outcome: real.("outcome.md"),
    savepoint: savepoint_shows_progress?(File.join(dir, "savepoint.md")),
    checklist_partial: real.("checklist.md") && checklist_partially_done?(File.join(dir, "checklist.md")),
    body_has_context: body.include?("## Context"),
    last_accessed_at: last_accessed_at(dir, (fm["created"].to_s rescue "")),
    done_at: done_timestamp(dir),
    # Kept only in the internal record so project Active rows can inspect the
    # durable lock beside the intent. intent_line deliberately does not expose
    # this filesystem path in --data or any rendered surface.
    intent_dir: File.expand_path(dir),
  }
end

def checklist_partially_done?(path)
  txt = File.read(path)
  checked = txt.scan(/^\s*- \[x\]/i).size
  total = txt.scan(/^\s*- \[[ x]\]/i).size
  checked.positive? && checked < total
rescue StandardError
  false
end

# Load every intent across all stores, with a completion-id set for unblock detection.
def load_all
  all = []
  done_ids = {}
  completed_on_map = {}
  stores.each do |si|
    idx = {
      active: index_section_ids(si[:index], "## Active"),
      abandoned: index_section_ids(si[:index], "## Abandoned"),
      completed: index_section_ids(si[:index], "## Completed"),
    }
    comp = completion_dates(si[:index])
    intent_dirs(si[:store]).each do |d|
      rec = parse_intent(si, d, idx)
      next unless rec
      rec[:completed_on] = comp[rec[:id]] || ""
      all << rec
      done_ids[[rec[:scope], rec[:id]]] = true if rec[:status] == "completed"
      completed_on_map[[rec[:scope], rec[:id]]] = comp[rec[:id]] if comp[rec[:id]] && !comp[rec[:id]].empty?
    end
  end
  referenced = {}
  all.each { |r| r[:sources].each { |s| referenced[[r[:scope], s]] = true } }
  [all, done_ids, referenced, completed_on_map]
end

# ---------------------------------------------------------------------------
# Classification — deterministic Value x Effort + disposition
# ---------------------------------------------------------------------------

def intent_type(rec)
  tags = rec[:tags].map(&:to_s)
  return "research" if tags.include?("research")
  return "exploration" if tags.include?("exploration")
  return "bugfix" if tags.include?("bugfix")
  "implementation"
end

def root_intent?(id)
  id.match?(/\A\d+\z/)
end

def folgezettel_depth(id)
  id.scan(/\d+|[a-z]+/).size
end

def lifecycle_stage(rec)
  return "done" if rec[:outcome]
  return "exec" if rec[:checklist]
  return "how" if rec[:plan]
  return "why" if rec[:spec]
  return "why" if rec[:body_has_context]
  "what"
end

# Effort -> :small | :big
# Small when the work is bounded: a non-implementation type, an already-scoped intent
# (plan/checklist exists), or a branch id. By Plastic's own Zettelkasten convention, a
# branch id is a narrower refinement of its parent, so any branch (not only deep
# sub-branches) defaults to smaller effort than an untouched root idea; root ids
# (`root_intent?`) are unaffected since `folgezettel_depth` on a bare number is always 1.
def effort_of(rec, type)
  return :small if %w[research exploration bugfix].include?(type)
  return :small if rec[:plan] || rec[:checklist]
  return :small if folgezettel_depth(rec[:id]) >= 2
  :big
end

# Value -> :high | :low (explicit frontmatter field wins).
# High is deliberately rare: an explicit stamp, a human-authored root idea, or an intent
# that has SPAWNED follow-on work, i.e. a strategic theme the user owns. "Has spawned work"
# means a reciprocal (I1) edge: another intent lists this one in its `sources`, captured by
# `referenced`. A purely relational `chain` entry (D2, no reciprocal `sources`) does NOT
# count as spawned, so bare `chain` membership is not a high-value signal (intent 68).
def value_of(rec, referenced = {})
  case rec[:value_field]
  when "high" then return :high
  when "low"  then return :low
  end
  return :high if rec[:author] == "human" && root_intent?(rec[:id])
  return :high if referenced[[rec[:scope], rec[:id]]]
  :low
end

def flags_of(rec, done_ids, completed_on_map = {})
  flags = []
  flags << "in-progress" if rec[:savepoint] || rec[:checklist_partial]
  if rec[:status] == "future" && !rec[:sources].empty? &&
     rec[:sources].all? { |s| done_ids[[rec[:scope], s]] } &&
     genuine_wait?(rec, completed_on_map)
    flags << "unblocked"
  end
  age = stale_age(rec)
  flags << "stale" if rec[:status] == "future" && age && age >= STALE_DAYS
  flags
end

# True iff at least one declared source's completion date is strictly later
# than this intent's own `created` date — i.e. the intent actually waited on
# something, rather than being born already-satisfied (the common case: a
# branch's declared source is almost always finished before the branch exists,
# since the child is created from the parent's own lifecycle).
def genuine_wait?(rec, completed_on_map)
  created_date = (Date.parse(rec[:created]) rescue nil)
  return false unless created_date
  rec[:sources].any? do |s|
    source_date_str = completed_on_map[[rec[:scope], s]]
    next false unless source_date_str
    source_date = (Date.parse(source_date_str) rescue nil)
    source_date && source_date > created_date
  end
end

def stale_age(rec)
  return nil if rec[:created].nil? || rec[:created].empty?
  (today - Date.parse(rec[:created])).to_i
rescue StandardError
  nil
end

QUADRANTS = {
  [:high, :small] => "quick_win",
  [:high, :big]   => "next_big",
  [:low, :small]  => "defer",
  [:low, :big]    => "triage",
}.freeze

# Disposition verb: research overrides by type; else by quadrant.
def disposition_of(type, quadrant)
  return "research" if %w[research exploration].include?(type)
  case quadrant
  when "next_big" then "drive"
  when "quick_win", "defer" then "defer"
  else "triage"
  end
end

def classify(rec, done_ids, referenced = {}, completed_on_map = {})
  type = intent_type(rec)
  value = value_of(rec, referenced)
  effort = effort_of(rec, type)
  quadrant = QUADRANTS[[value, effort]]
  disposition = disposition_of(type, quadrant)
  flags = flags_of(rec, done_ids, completed_on_map)
  rec.merge(
    type: type, value: value, effort: effort, quadrant: quadrant,
    lifecycle: lifecycle_stage(rec), flags: flags, disposition: disposition,
  )
end

# Only intents that are open work (not done/abandoned).
def actionable?(rec)
  %w[future active].include?(rec[:status])
end

# Priority rank key: value, flag urgency, effort.
def rank_key(rec)
  v = rec[:value] == :high ? 0 : 1
  f = if rec[:flags].include?("in-progress") then 0
      elsif rec[:flags].include?("unblocked") then 1
      else 2 end
  e = rec[:effort] == :small ? 0 : 1
  [v, f, e, rec[:id]]
end

# ---------------------------------------------------------------------------
# Glyphs
# ---------------------------------------------------------------------------

LIFECYCLE_GLYPH = { "what" => "○", "why" => "◔", "how" => "◑", "exec" => "◕", "done" => "●" }.freeze
DISPOSITION_GLYPH = { "drive" => "▸", "defer" => "⇢", "research" => "⊙", "triage" => "⚑" }.freeze
LEGEND = "legend  ○ What ◔ Why ◑ How ◕ Exec ● Done │ ▸drive ⇢defer ⊙research ⚑triage │ ⇡unblocked"

# Markdown board glyphs (intent 37). Status signature for the project active/future lists.
STATUS_GLYPH = { "active" => "◑", "completed" => "●", "future" => "○" }.freeze

# ---------------------------------------------------------------------------
# Rendering helpers
# ---------------------------------------------------------------------------

# Pad/truncate to a fixed cell width (glyphs counted as one cell).
def pad(str, width)
  s = str.to_s
  s = "#{s[0, width - 1]}…" if s.length > width
  s + (" " * (width - s.length))
end

CELL_CAP = 6

# Markdown-board caps (Task 5, D6/D7 of intent 37; re-tuned by intent 202 D1/D5): the ASCII
# renderer still caps via CELL_CAP/cap_cell, untouched. ACTIVE_CAP/NEXT_WORK_CAP are the
# --data board's DEFAULTS only: --limit-active/--limit-next override either one per call,
# and --all lifts both to unbounded (see main). Whatever is actually shown, the payload
# always reports the true pool size alongside it, so the footer can state an honest count
# instead of a silent "+N more" row (D5).
ACTIVE_CAP = 3
NEXT_WORK_CAP = 5
INTENT_LINE_MAX_CHARS = 120

# D1 fix (intent 202 gate review): the "most recently delivered" summary must read as 2 to
# 3 short sentences, never the longest thing on the board. SUMMARY_CHAR_BUDGET is the hard
# ceiling on the fully assembled string (about what 2 to 3 plain sentences read as).
# SUMMARY_TITLE_MAX_CHARS bounds each per-intent label before assembly, so the normal case
# (short titles) never needs the hard cap at all; the hard cap is the safety net that holds
# even when every intent's `intent` field is a full paragraph.
SUMMARY_CHAR_BUDGET = 320
SUMMARY_TITLE_MAX_CHARS = 48

def matrix(records, scope_tag: false)
  cells = { "quick_win" => [], "next_big" => [], "defer" => [], "triage" => [] }
  research = []
  records.each do |r|
    if %w[research exploration].include?(r[:type])
      research << r
    else
      cells[r[:quadrant]] << r
    end
  end
  cells.each_value { |list| list.sort_by! { |r| rank_key(r) } }
  research.sort_by! { |r| rank_key(r) }

  cw = 30
  out = []
  out << "                      EFFORT →   small                 big"
  out << "        ┌#{'─' * cw}┬#{'─' * cw}┐"
  out << "  value │ #{pad('QUICK WIN', cw - 1)}│ #{pad('★ NEXT BIG THING', cw - 1)}│"
  out.concat(cell_rows(cells["quick_win"], cells["next_big"], cw, scope_tag))
  out << "        ├#{'─' * cw}┼#{'─' * cw}┤"
  out << "   low  │ #{pad('DEFER → agent          ⇢', cw - 1)}│ #{pad('TRIAGE / question      ⚑', cw - 1)}│"
  out.concat(cell_rows(cells["defer"], cells["triage"], cw, scope_tag))
  out << "        └#{'─' * cw}┴#{'─' * cw}┘"
  unless research.empty?
    names = research.map { |r| "#{r[:id]} #{r[:intent]}" }.join(" · ")
    out << "  RESEARCH → agent  ⊙   #{names}"
  end
  out
end

def cell_entry(rec, width, scope_tag)
  return pad("", width) if rec.nil?
  flag = rec[:flags].include?("unblocked") ? " ⇡" : ""
  scope = scope_tag && !rec[:scope].to_s.empty? ? " (#{rec[:scope].sub('project:', '')})" : ""
  text = rec[:id].to_s.empty? ? "   #{rec[:intent]}" : " #{rec[:id]}  #{rec[:intent]}"
  pad("#{text}#{flag}#{scope}", width)
end

# Cap a cell's list to CELL_CAP entries, appending a "+N more" marker when truncated.
def cap_cell(list)
  return list if list.size <= CELL_CAP
  list.first(CELL_CAP) + [{ id: "", intent: "+#{list.size - CELL_CAP} more", flags: [], scope: "" }]
end

def cell_rows(left, right, cw, scope_tag)
  left = cap_cell(left)
  right = cap_cell(right)
  rows = [left.size, right.size, 1].max
  (0...rows).map do |i|
    "        │#{cell_entry(left[i], cw, scope_tag)}│#{cell_entry(right[i], cw, scope_tag)}│"
  end
end

# ---------------------------------------------------------------------------
# Text renderers
# ---------------------------------------------------------------------------

def header(title, right = "")
  pad_to = 70
  inner = pad("  PLASTIC · #{title}", pad_to - right.length - 2) + right
  ["╔#{'═' * pad_to}╗", "║#{pad(inner, pad_to)}║", "╚#{'═' * pad_to}╝"]
end

def render_continue(records)
  out = []
  out.concat(header("continue", today.to_s))
  out << ""
  out << "WHERE WE ARE  ·  active + last touched"
  out << ("─" * 70)
  active = records.select { |r| r[:status] == "active" }.sort_by { |r| rank_key(r) }
  recent = records.select { |r| r[:status] == "completed" && !r[:completed_on].empty? }
                  .sort_by { |r| r[:completed_on] }.reverse.first(3)
  active.each do |r|
    out << "  #{LIFECYCLE_GLYPH[r[:lifecycle]]} #{pad(r[:id], 6)}#{pad(r[:intent], 38)}  #{pad(r[:scope].sub('project:', ''), 9)} #{DISPOSITION_GLYPH[r[:disposition]]} #{r[:disposition]}"
  end
  recent.each do |r|
    out << "  ● #{pad(r[:id], 6)}#{pad(r[:intent], 38)}  #{pad(r[:scope].sub('project:', ''), 9)} done"
  end
  out << "  (none)" if active.empty? && recent.empty?
  out << ""
  out << "WHERE WE GO NEXT  ·  value × effort  (all scopes)"
  open = records.select { |r| actionable?(r) && r[:status] != "active" }
  out.concat(matrix(open, scope_tag: true))
  out << ""
  out << LEGEND
  out << "ask    for the <slug> project board  ·  plastic-auto  (works the dispatchable queue)"
  out.join("\n") + "\n"
end

def render_project(records, slug)
  scoped = records.select { |r| r[:scope] == "project:#{slug}" }
  active = scoped.select { |r| r[:status] == "active" }
  nxt = scoped.count { |r| r[:status] == "future" }
  out = []
  out.concat(header("project:#{slug}", "#{scoped.size} intents · #{active.size} active · #{nxt} next"))
  out << ""
  if active.empty?
    out << "ACTIVE   (none)"
  else
    active.each do |r|
      out << "ACTIVE   #{LIFECYCLE_GLYPH[r[:lifecycle]]} #{pad(r[:id], 6)}#{pad(r[:intent], 32)}#{DISPOSITION_GLYPH[r[:disposition]]} #{r[:disposition]}"
    end
  end
  out << ""
  out << "WHERE WE GO NEXT  ·  value × effort"
  out.concat(matrix(scoped.select { |r| r[:status] == "future" }, scope_tag: false))
  out << ""
  out << LEGEND
  out.join("\n") + "\n"
end

def render_all(records)
  out = []
  out.concat(header("all scopes", today.to_s))
  out << ""
  stores.map { |s| s[:scope] }.each do |scope|
    scoped = records.select { |r| r[:scope] == scope }
    next if scoped.empty?
    a = scoped.count { |r| r[:status] == "active" }
    f = scoped.count { |r| r[:status] == "future" }
    d = scoped.count { |r| r[:status] == "completed" }
    out << "  #{pad(scope, 20)} #{pad("#{scoped.size} intents", 14)} active #{a} · next #{f} · done #{d}"
  end
  out << ""
  out << LEGEND
  out.join("\n") + "\n"
end

# ---------------------------------------------------------------------------
# Store health — runs doctor's scoped store check on dashboard load.
#
# Each board load runs `doctor --store <scope>` (global board -> :global,
# project board -> the slug) and surfaces a compact store-health line in the
# payload. Invoked IN-PROCESS (Doctor.new + run_store_checks) rather than
# shelling out: it is hermetic for tests (same PLASTIC_HOME), faster (no second
# Ruby boot), and avoids parsing a subprocess's JSON. Non-fatal by contract: a
# warn/fail result is data only and never crashes the board or changes its exit.
# ---------------------------------------------------------------------------

def store_health(scope)
  result = Doctor.new(plastic_home: PLASTIC_HOME).run_store_checks(scope)
  failing = (result[:checks] || []).reject { |c| c[:status] == "pass" }
                                   .map { |c| c[:name] }
  {
    scope: scope.is_a?(Symbol) ? scope.to_s : scope,
    status: result[:status],
    summary: result[:summary],
    failing_checks: failing,
  }
rescue StandardError => e
  # Never let a store-health probe take down the dashboard.
  { scope: scope.is_a?(Symbol) ? scope.to_s : scope,
    status: "warn", summary: { pass: 0, warn: 1, fail: 0, total: 1 },
    failing_checks: ["store_health_probe_error"], error: e.message }
end

# ---------------------------------------------------------------------------
# Markdown-board data payload (intent 37) — heavy side; the skill fills a
# Markdown template from this and presents it. Deterministic, golden-tested.
# ---------------------------------------------------------------------------

# Descending sort key for an ISO8601 / date string without reversing arrays.
def invert_ts(ts)
  ts.to_s.ljust(20).chars.map { |c| 255 - c.ord }
end

# D2 "finish first": lifecycle stage descending (Exec, How, Why, What). "done" is included
# only defensively; it never appears in Active (status must be "active" to reach this sort).
# A later savepoint timestamp breaks a tie within the same stage. This is a NEW sort key,
# separate from rank_key: D3 leaves ranking untouched, so rank_key itself is not edited.
LIFECYCLE_FINISH_RANK = { "exec" => 0, "how" => 1, "why" => 2, "what" => 3, "done" => 4 }.freeze

def finish_first_key(rec)
  [LIFECYCLE_FINISH_RANK.fetch(rec[:lifecycle], 9), invert_ts(rec[:last_accessed_at])]
end

# Collapse whitespace to single spaces, strip, then escape Markdown table pipes so
# free-text payload data is safe to drop verbatim into a table cell. Block-form gsub
# avoids replacement-string backslash pitfalls.
def cell(s)
  s.to_s.gsub(/\s+/, " ").strip.gsub("|") { "\\|" }
end

# Truncate an intent title to the shared line budget, ellipsis when over.
def truncate_intent(text)
  t = text.to_s
  t.length > INTENT_LINE_MAX_CHARS ? "#{t[0, INTENT_LINE_MAX_CHARS]}…" : t
end

# Truncate `text` to at most `max_chars`, cutting at the last whitespace at or before the
# limit (never mid-word) and appending a single ellipsis character when truncation happens.
# recent_delivery_summary (D1 fix) uses this twice: once per intent label, so a
# paragraph-long `intent` field collapses to a short name, and once on the fully assembled
# summary string, the hard budget cap that holds no matter how the per-label math adds up.
def truncate_on_word_boundary(text, max_chars)
  t = text.to_s
  return t if t.length <= max_chars
  ellipsis = "…"
  limit = [max_chars - ellipsis.length, 0].max
  slice = t[0, limit]
  cut = slice.rindex(/\s/)
  slice = slice[0, cut] if cut && cut.positive?
  "#{slice.rstrip}#{ellipsis}"
end

# D3 fix (intent 202 gate review): completion dates only carry day granularity, and many
# intents can share a single day, so completed_on alone left Array#sort_by to break the tie
# however it fell out (not documented as stable, so nothing here relied on input order being
# preserved). This key makes the tie-break real, in priority order:
#   1. completed_on: the date already recorded in the store's "## Completed" section.
#   2. done_at (see done_timestamp above): the savepoint's own "Done" timestamp, when the
#      intent has one. This is the true completion moment, so it breaks a same-day tie
#      honestly instead of arbitrarily. Missing it (nil, mapped to "") sorts behind any
#      intent that does have one, since we never invent a plausible-looking time for it.
#   3. scope + id: always present and always unique (no two records share both), so two
#      intents can never compare equal here. This is the deterministic fallback of last
#      resort for intents with no Done timestamp on either side, chosen for exactly one
#      reason: it removes every remaining "whatever sort_by happened to do" case.
# Ascending; callers reverse the sorted list to read most-recent-first.
def delivery_recency_key(rec)
  [rec[:completed_on].to_s, rec[:done_at] || "", rec[:scope].to_s, rec[:id].to_s]
end

# Prose "what was delivered most recently" (D1), built once here so both the Markdown
# board and --plain get byte-identical wording for the same store state. Sourced from
# completed intents with a non-empty completed_on, most-recent-first - the SAME basis
# render_continue already uses for its "last touched" line, generalized to take an optional
# project scope. Deliberately NOT recently_worked's 24h window: a project not touched today
# would otherwise wrongly report nothing delivered even when its last delivery was real and
# recent.
def recent_delivery_summary(records, project_scope: nil, limit: 3)
  in_scope = records.select { |r| r[:status] == "completed" && !r[:completed_on].to_s.empty? &&
                                    (project_scope.nil? || r[:scope] == project_scope) }
  done_total = records.count { |r| r[:status] == "completed" &&
                                     (project_scope.nil? || r[:scope] == project_scope) }
  recent = in_scope.sort_by { |r| delivery_recency_key(r) }.reverse.first(limit)
  scope_phrase = project_scope.nil? ? " across all projects" : ""
  return "Nothing has been delivered#{scope_phrase} yet." if recent.empty?

  # Short per-intent label (D1): never the full `intent` paragraph, always id + a
  # word-boundary-truncated title, so one huge intent text cannot dominate the summary.
  titles = recent.map { |r| "#{r[:id]} #{truncate_on_word_boundary(r[:intent], SUMMARY_TITLE_MAX_CHARS)}".strip }
  headline =
    if titles.size == 1
      "Most recently delivered: #{titles.first} (#{recent.first[:completed_on]})."
    else
      "Most recently delivered: #{titles[0...-1].join(', ')} and #{titles.last} " \
      "(most recent #{recent.first[:completed_on]})."
    end
  summary = "#{headline} #{done_total} intent#{'s' unless done_total == 1} completed#{scope_phrase} in total."
  # Hard cap (D1): guarantees the invariant regardless of how the per-title math above adds
  # up, e.g. very long ids or an unusually large done_total driving the closing sentence
  # over budget on its own.
  truncate_on_word_boundary(summary, SUMMARY_CHAR_BUDGET)
end

# Honest-totals footer (D5): built once here so the Markdown board and --plain state the
# same true counts in the same words. active_shown/active_total are omitted on the global
# board (it has no Active list of its own).
def footer_line(next_shown:, next_total:, active_shown: nil, active_total: nil)
  if active_shown
    "Showing #{active_shown} of #{active_total} active, #{next_shown} of #{next_total} " \
    "next work. Ask for \"more\" or \"all\" to see everything, or run " \
    "`dashboard.rb project <slug> --plain` for the full plain-text board."
  else
    "Showing #{next_shown} of #{next_total} next work across all projects. Ask for " \
    "\"more\" or \"all\" to see everything, or run `dashboard.rb continue --plain` for " \
    "the full plain-text board."
  end
end

ANSI_ESCAPE_RE = /\e\[[0-?]*[ -\/]*[@-~]/

def safe_active_value(value, max_chars: INTENT_LINE_MAX_CHARS)
  text = value.to_s.gsub(ANSI_ESCAPE_RE, "").gsub(/[[:cntrl:]]+/, " ")
  # Idempotent because the composed worker/activity values pass through this
  # helper once per component and once after composition.
  normalized = text.gsub(/\s+/, " ").strip.gsub(/(?<!\\)\|/) { "\\|" }
  normalized.length > max_chars ? "#{normalized[0, max_chars]}…" : normalized
end

def display_provenance(value)
  # Worker combines agent and harness; bound each half so one hostile or merely
  # verbose value cannot crowd the other identity out of the shared line budget.
  text = safe_active_value(value, max_chars: INTENT_LINE_MAX_CHARS / 2 - 4)
  return "Unknown" if text.empty? || text.casecmp("unknown").zero?
  %w[claude codex].include?(text.downcase) ? text.capitalize : text
end

def active_lock_fields(rec, now:)
  view = Lock.who(rec.fetch(:intent_dir), now: now)
  owner = view["owner"] || {}
  worker = "#{display_provenance(owner['agent'])} · #{display_provenance(owner['harness'])}"
  activity = case view["state"]
             when "fresh" then "Fresh"
             when "stale" then "Stale"
             when "corrupt" then "Corrupt"
             else "No lock"
             end
  if view["state"] == "fresh"
    claim = Array(view["claims"]).find { |item| item["fresh"] && !item["corrupt"] }
    writer = claim && safe_active_value(claim["delegate"] || claim["owner_session"],
                                        max_chars: INTENT_LINE_MAX_CHARS - 20)
    activity = "#{activity} · writer #{writer}" unless writer.to_s.empty?
  end
  [worker, activity]
end

def intent_line(rec, bullet, now: Time.now)
  note = rec[:status] == "active" ? " (#{rec[:lifecycle].to_s.capitalize})" : ""
  text = rec[:intent].to_s
  text = "#{text[0, INTENT_LINE_MAX_CHARS]}…" if text.length > INTENT_LINE_MAX_CHARS
  row = { id: rec[:id], intent: rec[:intent], created: rec[:created], bullet: bullet,
    scope: rec[:scope], what: cell(text), stage: rec[:lifecycle].to_s.capitalize,
    line: "#{bullet} #{rec[:id]} #{text}#{note}".rstrip }
  if rec[:status] == "active"
    worker, activity = active_lock_fields(rec, now: now)
    row[:worker] = safe_active_value(worker)
    row[:activity] = safe_active_value(activity)
    row[:line] = "#{row[:line]} · #{row[:worker]} · #{row[:activity]}"
  end
  row
end

# Cap an already-sorted record list to `cap` entries and map to intent_line-shaped hashes.
# No trailing "+N more" marker (D5, intent 202): the payload's own *_total/*_shown fields
# (see render_data_project) carry the honest count, and the footer states it in prose, so a
# fake blank row is no longer needed here.
def capped_rows(list, bullet, cap, now: Time.now)
  list.first(cap).map { |r| intent_line(r, bullet, now: now) }
end

# Flat, rank-ordered "most-valuable next work" list (intent 149), capped at `cap` (default
# NEXT_WORK_CAP; --data mode overrides via --limit-next or lifts it via --all, see main). No
# trailing "+N more" marker (D5, intent 202): render_data_project/render_data_global report
# the true pool size alongside this capped list, and the footer states it in prose. No grid
# glyph on the line; the prose surface supplies its own bullet.
def next_work(records, cap: NEXT_WORK_CAP)
  ranked = records.sort_by { |r| rank_key(r) }
  ranked.first(cap).map do |r|
    text = r[:intent].to_s
    text = "#{text[0, INTENT_LINE_MAX_CHARS]}…" if text.length > INTENT_LINE_MAX_CHARS
    { id: r[:id], intent: r[:intent], scope: r[:scope], lifecycle: r[:lifecycle],
      value: r[:value].to_s, disposition: r[:disposition], flags: r[:flags],
      what: cell(text), flags_label: cell(Array(r[:flags]).join(", ")),
      line: "#{r[:id]} #{text}" }
  end
end

def short_description(scope)
  return "" unless scope.start_with?("project:")
  slug = scope.sub("project:", "")
  agents = File.join(PLASTIC_HOME, "projects", slug, "AGENTS.md")
  if File.exist?(agents)
    File.readlines(agents).each do |l|
      t = l.strip
      next if t.empty? || t.start_with?("#", ">")
      return t[0, 60]
    end
  end
  slug
end

def project_summaries(records)
  scopes = records.map { |r| r[:scope] }.select { |s| s.start_with?("project:") }.uniq
  rows = scopes.map do |scope|
    scoped = records.select { |r| r[:scope] == scope }
    {
      slug: scope.sub("project:", ""),
      description: short_description(scope),
      active: scoped.count { |r| r[:status] == "active" },
      done: scoped.count { |r| r[:status] == "completed" },
      future: scoped.count { |r| r[:status] == "future" },
      last_accessed_at: scoped.map { |r| r[:last_accessed_at] }.reject(&:empty?).max.to_s,
    }
  end
  rows.sort_by { |r| invert_ts(r[:last_accessed_at]) }.first(5)
end

def counts_of(records)
  { active: records.count { |r| r[:status] == "active" },
    done: records.count { |r| r[:status] == "completed" },
    future: records.count { |r| r[:status] == "future" } }
end

def render_data_global(records, next_limit: NEXT_WORK_CAP, all: false)
  global = records.select { |r| r[:scope] == "global" }
  matrix_pool = global.select { |r| actionable?(r) && r[:status] != "active" }
  next_cap = all ? matrix_pool.size : next_limit
  next_shown = [next_cap, matrix_pool.size].min
  projs = project_summaries(records)
  { mode: "global", date: today.to_s,
    store_health: store_health(:global),
    summary: recent_delivery_summary(records, project_scope: nil),
    next_work: next_work(matrix_pool, cap: next_cap),
    next_total: matrix_pool.size,
    next_shown: next_shown,
    counts: counts_of(global),
    projects: projs,
    project_totals: {
      active: projs.sum { |p| p[:active] }, done: projs.sum { |p| p[:done] },
      future: projs.sum { |p| p[:future] }
    },
    footer: footer_line(next_shown: next_shown, next_total: matrix_pool.size) }
end

def render_data_project(records, slug, active_limit: ACTIVE_CAP, next_limit: NEXT_WORK_CAP,
                        all: false, now: Time.now)
  scope = "project:#{slug}"
  scoped = records.select { |r| r[:scope] == scope }
  active_pool = scoped.select { |r| r[:status] == "active" }.sort_by { |r| finish_first_key(r) }
  next_pool = scoped.select { |r| r[:status] == "future" }

  active_cap = all ? active_pool.size : active_limit
  next_cap = all ? next_pool.size : next_limit
  active_shown = [active_cap, active_pool.size].min
  next_shown = [next_cap, next_pool.size].min

  { mode: "project", date: today.to_s, slug: slug,
    store_health: store_health(slug),
    description: short_description(scope),
    summary: recent_delivery_summary(records, project_scope: scope),
    counts: counts_of(scoped),
    active: capped_rows(active_pool, STATUS_GLYPH["active"], active_cap, now: now),
    active_total: active_pool.size,
    active_shown: active_shown,
    next_work: next_work(next_pool, cap: next_cap),
    next_total: next_pool.size,
    next_shown: next_shown,
    footer: footer_line(active_shown: active_shown, active_total: active_pool.size,
                         next_shown: next_shown, next_total: next_pool.size) }
end

# --plain (D4): the full, uncapped board as plain text, no Markdown table syntax, meant to
# pipe cleanly into a real pager (`less`). Reuses the exact same payload builders --data
# uses, with all: true, and prints the `summary`/`.line`/`footer` fields those builders
# already compute -- no separate selection or sorting logic lives here.
def render_plain_project(records, slug)
  payload = render_data_project(records, slug, all: true)
  lines = []
  lines << "#{slug} - Project Board, #{payload[:date]}"
  lines << payload[:description] unless payload[:description].to_s.empty?
  lines << ""
  lines << payload[:summary]
  lines << ""
  lines << "Active (#{payload[:active_total]})"
  lines.concat(payload[:active].empty? ? ["(none)"] : payload[:active].map { |r| r[:line] })
  lines << ""
  lines << "Most-valuable next work (#{payload[:next_total]})"
  lines.concat(payload[:next_work].empty? ? ["(none)"] : payload[:next_work].map { |r| r[:line] })
  lines << ""
  lines << payload[:footer]
  lines.join("\n") + "\n"
end

def render_plain_global(records)
  payload = render_data_global(records, all: true)
  counts = payload[:counts]
  lines = []
  lines << "Plastic - Global Board, #{payload[:date]}"
  lines << ""
  lines << payload[:summary]
  lines << ""
  lines << "#{counts[:active]} intents active, #{counts[:done]} done, #{counts[:future]} queued for later."
  lines << ""
  lines << "Most-valuable next work (#{payload[:next_total]})"
  lines.concat(payload[:next_work].empty? ? ["(none)"] : payload[:next_work].map { |r| r[:line] })
  lines << ""
  lines << payload[:footer]
  lines.join("\n") + "\n"
end

# ---------------------------------------------------------------------------
# JSON renderer (agent / auto-mode contract)
# ---------------------------------------------------------------------------

def render_json(records, scope_label)
  ranked = records.select { |r| actionable?(r) }.sort_by { |r| rank_key(r) }
  dispatchable = ranked.select { |r| %w[defer research].include?(r[:disposition]) }
  human_only = ranked.select { |r| %w[drive triage].include?(r[:disposition]) }
  nbt = ranked.find { |r| r[:disposition] == "drive" }
  {
    generated_for: "auto-mode",
    scope: scope_label,
    next_big_thing: nbt && nbt[:id],
    dispatchable_queue: dispatchable.each_with_index.map do |r, i|
      { id: r[:id], scope: r[:scope], disposition: r[:disposition], type: r[:type],
        value: r[:value].to_s, effort: r[:effort].to_s, flags: r[:flags], rank: i + 1 }
    end,
    human_only: human_only.map { |r| r[:id] },
  }
end

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

# JSON.pretty_generate renders empty arrays/objects as multi-line ("[\n\n  ]") on
# some json gem versions and single-line ("[]") on others, so the same payload
# serializes differently across environments. Collapse both to the single-line
# form so dashboard JSON output is byte-identical everywhere. The \n requirement
# in each pattern is what makes this safe: a raw newline is illegal inside a JSON
# string, so neither pattern can ever match inside string content.
def canonical_pretty_json(payload)
  JSON.pretty_generate(payload).gsub(/\[\s*\n\s*\]/, "[]").gsub(/\{\s*\n\s*\}/, "{}")
end

# Pull a "--flag value" pair out of argv, mutating it in place; returns the value string,
# or nil when the flag is absent. Unlike --json/--data/--all (bare toggles),
# --limit-active/--limit-next carry a value.
def extract_flag_value(argv, flag)
  idx = argv.index(flag)
  return nil unless idx
  argv.delete_at(idx)
  argv.delete_at(idx)
end

def main(argv)
  json = argv.delete("--json")
  data = argv.delete("--data")
  plain = argv.delete("--plain")
  all = argv.delete("--all")
  limit_active = extract_flag_value(argv, "--limit-active")
  limit_next = extract_flag_value(argv, "--limit-next")
  mode = argv.shift || "continue"
  slug = argv.shift

  raw, done_ids, referenced, completed_on_map = load_all
  records = raw.map { |r| classify(r, done_ids, referenced, completed_on_map) }

  if data
    payload =
      if mode == "project"
        render_data_project(records, slug,
                             active_limit: (limit_active || ACTIVE_CAP).to_i,
                             next_limit: (limit_next || NEXT_WORK_CAP).to_i,
                             all: !!all)
      else
        render_data_global(records, next_limit: (limit_next || NEXT_WORK_CAP).to_i, all: !!all)
      end
    puts canonical_pretty_json(payload)
    return 0
  end

  if plain
    if mode == "project"
      if slug.nil? || slug.empty?
        warn "usage: dashboard.rb project <slug> --plain"
        return 2
      end
      print render_plain_project(records, slug)
    else
      print render_plain_global(records)
    end
    return 0
  end

  if json
    subset = mode == "project" ? records.select { |r| r[:scope] == "project:#{slug}" } : records
    label = mode == "project" ? "project:#{slug}" : "all"
    payload = render_json(subset, label)
    # Run the scoped store check on load, mirroring the --data board path:
    # project board -> the slug; global/continue board -> :global. The `all`
    # manifest spans every store, so its store-health probe is left to the
    # per-scope boards (keeping the all-scopes auto-mode contract stable).
    payload[:store_health] = store_health(slug) if mode == "project"
    payload[:store_health] = store_health(:global) if mode == "continue"
    puts canonical_pretty_json(payload)
    return 0
  end

  case mode
  when "continue" then print render_continue(records)
  when "project"
    if slug.nil? || slug.empty?
      warn "usage: dashboard.rb project <slug>"
      return 2
    end
    print render_project(records, slug)
  when "all" then print render_all(records)
  else
    warn "unknown mode: #{mode} (use continue|project <slug>|all)"
    return 2
  end
  0
end

exit(main(ARGV)) if $PROGRAM_NAME == __FILE__
