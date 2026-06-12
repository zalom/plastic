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

PLASTIC_HOME = ENV.fetch("PLASTIC_HOME") { File.join(Dir.home, ".plastic") }

def today
  s = ENV["DASHBOARD_TODAY"]
  s && !s.empty? ? Date.parse(s) : Date.today
end

STALE_DAYS = 14

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

# Map of intent id -> completion date string, parsed from the "## Completed" section
# (lines like "- [12 — ...](...) — 2026-06-10"). Deterministic, content-derived.
def completion_dates(index_path)
  return {} unless File.exist?(index_path)
  body = File.read(index_path)
  seg = body[/^## Completed\s*\n(.*?)(?=^## |\z)/m, 1] || ""
  seg.scan(/^- \[([^\]\s]+).*?—\s*(\d{4}-\d{2}-\d{2})\s*$/).to_h
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

# Parse one intent directory into a raw record.
def parse_intent(store_info, dir_name, status_index)
  dir = File.join(store_info[:store], dir_name)
  md = File.join(dir, "#{dir_name}.md")
  fm = parse_frontmatter(md)
  return nil unless fm && fm["id"]

  id = fm["id"].to_s
  has = ->(f) { File.exist?(File.join(dir, f)) }
  body = File.exist?(md) ? File.read(md) : ""

  status =
    if has.("outcome.md") then "completed"
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
    spec: has.("spec.md"),
    plan: has.("plan.md"),
    checklist: has.("checklist.md"),
    outcome: has.("outcome.md"),
    savepoint: has.("savepoint.md"),
    checklist_partial: has.("checklist.md") && checklist_partially_done?(File.join(dir, "checklist.md")),
    body_has_context: body.include?("## Context"),
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
    end
  end
  [all, done_ids]
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
# (plan/checklist exists), or a deep refinement branch. Otherwise big.
def effort_of(rec, type)
  return :small if %w[research exploration bugfix].include?(type)
  return :small if rec[:plan] || rec[:checklist]
  return :small if folgezettel_depth(rec[:id]) >= 4
  :big
end

# Value -> :high | :low (explicit frontmatter field wins).
# High is deliberately rare: an explicit stamp, or a human-authored root idea that has
# already spawned follow-on work (chain non-empty) — i.e. a strategic theme the user owns.
def value_of(rec)
  case rec[:value_field]
  when "high" then return :high
  when "low"  then return :low
  end
  return :high if rec[:author] == "human" && root_intent?(rec[:id]) && !rec[:chain].empty?
  :low
end

def flags_of(rec, done_ids)
  flags = []
  flags << "in-progress" if rec[:savepoint] || rec[:checklist_partial]
  if !rec[:sources].empty? && rec[:sources].any? { |s| done_ids[[rec[:scope], s]] }
    flags << "unblocked"
  end
  age = stale_age(rec)
  flags << "stale" if rec[:status] == "future" && age && age >= STALE_DAYS
  flags
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

def classify(rec, done_ids)
  type = intent_type(rec)
  value = value_of(rec)
  effort = effort_of(rec, type)
  quadrant = QUADRANTS[[value, effort]]
  disposition = disposition_of(type, quadrant)
  flags = flags_of(rec, done_ids)
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
  out << "run     plastic-dashboard project <slug>  ·  plastic-auto  (works the dispatchable queue)"
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

def main(argv)
  json = argv.delete("--json")
  mode = argv.shift || "continue"
  slug = argv.shift

  raw, done_ids = load_all
  records = raw.map { |r| classify(r, done_ids) }

  if json
    subset = mode == "project" ? records.select { |r| r[:scope] == "project:#{slug}" } : records
    label = mode == "project" ? "project:#{slug}" : "all"
    puts JSON.pretty_generate(render_json(subset, label))
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
