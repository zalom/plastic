#!/usr/bin/env ruby
# encoding: UTF-8

require "yaml"
require_relative "lock"

# Bridge - the shared helpers that outlived the /tmp bridge JSON.
#
# Until 2.0 this file cached a session's delivery state in
# `<tmp>/plastic-<session>--<id>.json` (stage, worktree, lock, auto flag) and
# arbitrated which bridge a gate hook should read. Ruling 6 of intent 296
# retired that: the per-session pointer (`~/.plastic/store/.tmp/<session>/current`)
# plus `delivery.lock` in the intent directory is the whole bridge, and
# `scripts/lib/arm.rb` is how a team takes and gives back an intent (intent
# 307). What stays here is the handful of pure helpers a dozen callers still
# share: the INDEX entry matcher, the Active check, the id-from-dir parser,
# the project config reader, `blank?`, and the skill-reference delegator.
module Bridge
  # Single place a skill-reference string gets built (intent 201, D3). The
  # prefix table lives on Lock; this is a thin delegator so call sites read
  # Bridge.skill_ref.
  def self.skill_ref(name, harness: :claude)
    Lock.skill_ref(name, harness: harness)
  end

  def self.blank?(value)
    value.nil? || value.to_s.strip.empty?
  end

  # --- Shared INDEX entry matcher (intent 188, D12/D13) -----------------------
  #
  # ONE definition site for the "- [ID <sep> Title](link)" shape both
  # `intent_active?` (below) and `scripts/end-intent`'s own INDEX-move parser
  # depend on, so the two regexes can never drift apart. Accepts a real em dash
  # (U+2014) OR a plain hyphen as the id/title separator on READ; every WRITE
  # still emits the real em dash (D10). The separator is built from the
  # codepoint, not a literal byte, so this file stays em-dash free.
  EM_DASH = "\u2014".freeze
  INDEX_ENTRY_RE = /\A- \[(\S+)\s+(?:#{Regexp.escape(EM_DASH)}|-)\s+(.*?)\]\(([^)]+)\)/.freeze

  # Match `line` (already chomped) against the shared INDEX entry shape.
  # Returns a MatchData (captures: 1 = id, 2 = title, 3 = link) or nil.
  def self.index_entry_match(line)
    line.to_s.match(INDEX_ENTRY_RE)
  end

  # True iff the intent is Active in its store's INDEX.md, which lives at the
  # PARENT of the store/ dir. Non-raising: any failure (missing or unreadable
  # INDEX, bad arg) returns false. `index_active_ids` is a pure-data test
  # seam: when an Array of id strings is supplied, membership is checked
  # against it directly with no file read.
  def self.intent_active?(intent_id, store:, index_active_ids: nil)
    target = intent_id.to_s
    return index_active_ids.include?(target) if index_active_ids.is_a?(Array)

    index = File.join(File.dirname(store.to_s), "INDEX.md")
    return false unless File.exist?(index)

    in_active = false
    File.foreach(index) do |line|
      stripped = line.chomp
      if stripped == "## Active"
        in_active = true
        next
      end
      next unless in_active
      break if stripped.start_with?("## ") # next section ends the Active block
      m = index_entry_match(stripped)
      return true if m && m[1] == target
    end
    false
  rescue StandardError
    false
  end

  # --- Project config -------------------------------------------------------------

  PROJECT_CONFIG_DEFAULTS = {
    "governing_docs" => ["AGENTS.md"],
    "release" => {
      "on_complete" => "commit",
    },
  }.freeze

  def self.read_project_config(slug)
    path = File.join(Dir.home, ".plastic", "projects", slug, "project.yml")
    config = if File.exist?(path)
               YAML.safe_load(File.read(path)) || {}
             else
               {}
             end

    deep_merge(PROJECT_CONFIG_DEFAULTS, config)
  rescue => e
    $stderr.puts "Warning: failed to read project config for #{slug}: #{e.message}"
    PROJECT_CONFIG_DEFAULTS.dup
  end

  # "<id>" from a ".../store/<id>--<slug>" dir, else nil.
  def self.intent_id_from_dir(dir)
    base = File.basename(dir.to_s)
    base.include?("--") ? base.split("--", 2).first : nil
  end

  def self.deep_merge(base, overlay)
    result = base.dup
    overlay.each do |key, value|
      if value.is_a?(Hash) && result[key].is_a?(Hash)
        result[key] = deep_merge(result[key], value)
      else
        result[key] = value
      end
    end
    result
  end
end
