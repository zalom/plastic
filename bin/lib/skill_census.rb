# encoding: UTF-8
# frozen_string_literal: true

require "json"
require "yaml"
require "date"
require "time"
require "set"

# SkillCensus (intent 324): counts typed /plastic-* commands against
# agent-invoked Skill calls, so D19 (which Plastic verbs stay visible as
# slash commands) is ruled on measured use rather than taste.
#
# Two sources, never mixed. `HistoryScanner` reads ~/.claude/history.jsonl
# for typed commands: the transcript tree is pruned to about 45 days and
# would undercount typed use by two orders of magnitude. `TranscriptScanner`
# reads the ~/.claude/projects tree for agent invocations, loads,
# attribution, and mentions. `Tally` maps both sources through the name
# map, and `Report` renders the result as Markdown or JSON.
#
# Maintainer tool: `bin/plastic-skill-census` lives beside `bin/plastic-bench`
# and is never installed into ~/.plastic. Stdlib only, no network, no eval.
#
# This file and its CLI never resolve the running process's home directory
# or its home environment variable: `bin/` ships in the npm tarball, so a
# default rooted there would make a published executable read any
# installer's transcripts. `--history` and `--transcripts` are required,
# with no default.
module SkillCensus
  DEFAULT_CUTOFF = "2026-09-02"

  NAME_MAP = {}.freeze

  # Retired without a successor (attested only).
  RETIRED = [
    "plastic-intent-discovering",
    "plastic-intent-discovery",
    "plastic-intent-curator",
    "plastic-skill-creating",
    "plastic-skill-evaluating",
    "plastic-humanizer",
    "plastic-intent-brainstorming",
    "plastic-brainstorming",
    "plastic-continuing",
    "plastic-project-continuing",
    "plastic-roadmap-continuing",
    "plastic-intent-starting",
    "plastic-intent-creating",
    "plastic-intent-speccing",
    "plastic-intent-planning",
    "plastic-intent-executing",
    "plastic-intent-ending",
    "plastic-intent-continuing",
    "plastic-install",
    "plastic-uninstall",
    "plastic-update",
    "plastic-rollback",
  ].freeze

  # ~/.plastic/scripts/* filenames, never skills (review 3). plastic-lock
  # alone occurs 257 times in the live files; mapping it into plastic-doctor
  # was the original map's worst counting bug.
  SCRIPTS = [
    "plastic-lock",
    "plastic-savepoint",
    "plastic-bench",
    "plastic-statusline",
    "plastic-session-start",
    "plastic-code-gate",
  ].freeze

  # Agent names, never skills (review 3).
  AGENTS = [
    "plastic-advisor",
    "plastic-faux-advisor",
    "plastic-enforcer",
    "plastic-executor",
    "plastic-future-intent-researcher",
  ].freeze

  # Roster skills this instrument cannot observe through the Skill tool or a
  # typed command, with the mechanism that reaches them instead (review 4).
  MECHANISMS = {
    "plastic-agent-advisor" => "dispatched as the plastic-advisor / plastic-faux-advisor subagent, not through the Skill tool",
    "plastic-conventions" => "read as references/*.md from inside other skills",
    "plastic-direct" => "routed by the SessionStart hook and PLASTIC.md",
    "plastic-feedback" => "routed by the SessionStart hook and PLASTIC.md",
  }.freeze

  PLASTIC_TYPED_RE = %r{\A\s*/(plastic[:-][a-z0-9][a-z0-9-]*)}.freeze
  PLASTIC_TAGGED_RE = %r{<command-name>\s*/(plastic[:-][a-z0-9][a-z0-9-]*)</command-name>}.freeze
  BUILTIN_TYPED_RE = %r{\A\s*/([a-zA-Z][a-zA-Z0-9_-]*)}.freeze
  MENTION_SCAN_RE = /plastic[:-][a-z0-9][a-z0-9-]*/.freeze
  LOAD_PREFIX = "Base directory for this skill:"

  # The pre-npm plugin colon namespace maps onto the hyphen form before the
  # name map is consulted (D10): plastic:update normalises to plastic-update.
  def self.normalize(raw)
    raw.sub(":", "-")
  end

  # One classified occurrence: a typed command, a call, a load, a mention.
  # `project` is set only by HistoryScanner (history records carry it);
  # `file` is set only by TranscriptScanner.
  Event = Struct.new(:name, :date, :project, :file, :detail, keyword_init: true)

  # -------------------------------------------------------------------
  # Roster - the current skill directories, from SKILL.md frontmatter.
  # -------------------------------------------------------------------
  module Roster
    Skill = Struct.new(:name, :user_invocable, keyword_init: true)

    def self.load(skills_dir)
      raise "skills dir not found: #{skills_dir}" unless File.directory?(skills_dir)

      Dir.children(skills_dir).sort.filter_map do |entry|
        dir = File.join(skills_dir, entry)
        next unless File.directory?(dir)

        skill_md = File.join(dir, "SKILL.md")
        next unless File.file?(skill_md)

        fm = frontmatter(File.read(skill_md))
        Skill.new(name: "plastic-#{entry}", user_invocable: fm["user-invocable"] == true)
      end
    end

    # skill_lint.rb's split: content.split("---", 3), parts[1] is the
    # frontmatter block. A missing or unparsable block reads as no flags,
    # which Roster.load turns into user_invocable: false, never a raise.
    def self.frontmatter(content)
      parts = content.split("---", 3)
      return {} if parts.length < 3

      YAML.safe_load(parts[1].to_s) || {}
    rescue Psych::SyntaxError
      {}
    end
  end

  # -------------------------------------------------------------------
  # HistoryScanner - typed commands from ~/.claude/history.jsonl.
  # -------------------------------------------------------------------
  class HistoryScanner
    Result = Struct.new(:record_count, :first_seen, :last_seen, :typed, :mentions,
                        :builtins, :self_generated, :monthly, keyword_init: true)

    def initialize(history_path, cutoff:)
      @path = history_path
      @cutoff = cutoff.is_a?(Date) ? cutoff : Date.parse(cutoff.to_s)
    end

    def scan
      raise "history file not found: #{@path}" unless File.file?(@path)

      record_count = 0
      typed = []
      mentions = []
      builtins = Hash.new(0)
      self_generated = []
      first_seen = nil
      last_seen = nil

      File.foreach(@path) do |raw_line|
        line = raw_line.strip
        next if line.empty?

        record = begin
          JSON.parse(line)
        rescue JSON::ParserError
          next
        end
        record_count += 1

        display = record["display"].to_s
        date = ms_to_date(record["timestamp"])
        project = record["project"]

        if date
          first_seen = date if first_seen.nil? || date < first_seen
          last_seen = date if last_seen.nil? || date > last_seen
        end
        after_cutoff = date && date >= @cutoff

        if (m = display.match(PLASTIC_TYPED_RE))
          event = Event.new(name: SkillCensus.normalize(m[1]), date: date, project: project, detail: display)
          after_cutoff ? self_generated << event : typed << event
        elsif (m = display.match(BUILTIN_TYPED_RE))
          builtins[m[1]] += 1 unless after_cutoff
        elsif display.match(MENTION_SCAN_RE)
          mentions << Event.new(name: nil, date: date, project: project, detail: display) unless after_cutoff
        end
      end

      monthly = Hash.new(0)
      typed.each { |e| monthly[e.date.strftime("%Y-%m")] += 1 if e.date }

      Result.new(record_count: record_count, first_seen: first_seen, last_seen: last_seen,
                 typed: typed, mentions: mentions, builtins: builtins,
                 self_generated: self_generated, monthly: monthly)
    end

    private

    def ms_to_date(ms)
      return nil unless ms

      Time.at(ms.to_f / 1000.0).utc.to_date
    end
  end

  # -------------------------------------------------------------------
  # TranscriptScanner - calls, loads, attribution, and mentions from the
  # ~/.claude/projects tree.
  # -------------------------------------------------------------------
  class TranscriptScanner
    Call = Struct.new(:name, :tool_use_id, :file, :date, keyword_init: true)
    Corroboration = Struct.new(:matched, :disagreements, keyword_init: true)

    Result = Struct.new(
      :files_top, :files_subagent, :record_count, :unparsable_lines,
      :first_seen, :last_seen,
      :calls_main, :calls_agent, :other_skills,
      :loads, :attributed, :mentions, :scripts, :agents,
      :transcript_typed, :self_generated, :corroboration,
      :self_generated_calls, :self_generated_loads,
      :self_generated_attributed, :self_generated_mentions,
      keyword_init: true
    )

    def initialize(transcripts_dir, cutoff:)
      @dir = transcripts_dir
      @cutoff = cutoff.is_a?(Date) ? cutoff : Date.parse(cutoff.to_s)
    end

    def scan
      raise "transcripts dir not found: #{@dir}" unless File.directory?(@dir)

      state = new_state
      Dir.glob(File.join(@dir, "**", "*.jsonl")).sort.each { |path| scan_file(path, state) }
      finish(state)
    end

    private

    def new_state
      {
        files_top: 0, files_subagent: 0, record_count: 0, unparsable_lines: 0,
        first_seen: nil, last_seen: nil,
        calls_main: [], calls_agent: [],
        other_skills: Hash.new { |h, k| h[k] = { calls: 0, loads: 0, attributed: 0 } },
        loads: [], attributed: Hash.new(0), mentions: [], scripts: Hash.new(0), agents: Hash.new(0),
        transcript_typed: [], self_generated: [],
        self_generated_calls: 0, self_generated_loads: 0,
        self_generated_attributed: 0, self_generated_mentions: 0,
        seen_tool_use_ids: Set.new, seen_uuids: Set.new,
        corroboration_by_id: Hash.new { |h, k| h[k] = {} },
      }
    end

    def scan_file(path, state)
      file_is_subagent = subagent_path?(path)
      state[file_is_subagent ? :files_subagent : :files_top] += 1

      File.foreach(path) do |raw_line|
        line = raw_line.strip
        next if line.empty?

        record = begin
          JSON.parse(line)
        rescue JSON::ParserError
          state[:unparsable_lines] += 1
          next
        end

        uuid = record["uuid"]
        next if uuid && !state[:seen_uuids].add?(uuid)

        state[:record_count] += 1
        classify_record(record, path, file_is_subagent, state)
      end
    end

    def classify_record(record, path, file_is_subagent, state)
      date = iso_to_date(record["timestamp"])
      track_span(date, state)
      after_cutoff = date && date >= @cutoff
      record_is_subagent = file_is_subagent || record["isSidechain"] == true || record.key?("agentId")

      if (attribution = record["attributionSkill"])
        if after_cutoff
          state[:self_generated_attributed] += 1
        elsif plastic_name?(attribution)
          state[:attributed][attribution] += 1
        else
          state[:other_skills][attribution][:attributed] += 1
        end
      end

      classify_tool_use(record, path, date, record_is_subagent, after_cutoff, state) if record["type"] == "assistant"
      classify_tool_result(record, after_cutoff, state)

      return unless record["type"] == "user"

      classify_user_text(record, path, date, after_cutoff, record_is_subagent, state)
    end

    def track_span(date, state)
      return unless date

      state[:first_seen] = date if state[:first_seen].nil? || date < state[:first_seen]
      state[:last_seen] = date if state[:last_seen].nil? || date > state[:last_seen]
    end

    def classify_tool_use(record, path, date, record_is_subagent, after_cutoff, state)
      each_content_block(record) do |block|
        next unless block.is_a?(Hash) && block["type"] == "tool_use" && block["name"] == "Skill"

        raw = block.dig("input", "skill").to_s
        next if raw.empty?

        # A post-cutoff block is counted only in the self-generated bucket and
        # never touches seen_tool_use_ids, so it cannot consume an id a
        # pre-cutoff block would later need (D16).
        if after_cutoff
          state[:self_generated_calls] += 1
          next
        end

        id = block["id"]
        next if id && !state[:seen_tool_use_ids].add?(id)

        # Only the plastic: colon namespace maps onto the hyphen form (D10);
        # a plugin-prefixed non-Plastic name like claudish-to-english:claudish
        # must appear verbatim in other_skills, not split on its own colon.
        name = raw.start_with?("plastic:") ? SkillCensus.normalize(raw) : raw
        call = Call.new(name: name, tool_use_id: id, file: path, date: date)
        if plastic_name?(name)
          (record_is_subagent ? state[:calls_agent] : state[:calls_main]) << call
        else
          state[:other_skills][name][:calls] += 1
        end
      end
    end

    def classify_tool_result(record, after_cutoff, state)
      return if after_cutoff

      content = message_content(record)
      return unless content.is_a?(Array)

      block = content.find { |b| b.is_a?(Hash) && b["type"] == "tool_result" }
      return unless block

      tool_use_id = block["tool_use_id"]
      return unless tool_use_id

      if record["toolUseResult"].is_a?(Hash) && record["toolUseResult"]["commandName"]
        state[:corroboration_by_id][tool_use_id][:command_name] = record["toolUseResult"]["commandName"]
      end

      text = block["content"]
      text = text.filter_map { |c| c["text"] if c.is_a?(Hash) }.join if text.is_a?(Array)
      if text.is_a?(String) && (m = text.match(/Launching skill:\s*(\S+)/))
        state[:corroboration_by_id][tool_use_id][:launching_text] = m[1]
      end
    end

    def classify_user_text(record, path, date, after_cutoff, record_is_subagent, state)
      text = extract_text(record)
      return if text.nil? || text.empty?

      if (load_name = load_name_from(text))
        if after_cutoff
          state[:self_generated_loads] += 1
        elsif plastic_name?(load_name)
          state[:loads] << Event.new(name: load_name, date: date, file: path)
        else
          state[:other_skills][load_name][:loads] += 1
        end
        remainder = text.sub(/\A.*#{Regexp.escape(LOAD_PREFIX)}[^\n]*\n?/m, "")
        scan_occurrences(remainder, path, date, after_cutoff, state)
        return
      end

      typed_name = tagged_or_bare_typed_name(text)
      if typed_name
        event = Event.new(name: typed_name, date: date, file: path, detail: text[0, 200])
        unless record_is_subagent
          after_cutoff ? state[:self_generated] << event : state[:transcript_typed] << event
        end
        return
      end

      scan_occurrences(text, path, date, after_cutoff, state)
    end

    def scan_occurrences(text, path, date, after_cutoff, state)
      matches = text.scan(MENTION_SCAN_RE)
      if after_cutoff
        state[:self_generated_mentions] += matches.length
        return
      end

      matches.each do |raw|
        name = SkillCensus.normalize(raw)
        if SCRIPTS.include?(name)
          state[:scripts][name] += 1
        elsif AGENTS.include?(name)
          state[:agents][name] += 1
        else
          state[:mentions] << Event.new(name: name, date: date, file: path)
        end
      end
    end

    def finish(state)
      disagreements = state[:corroboration_by_id].filter_map do |tool_use_id, sides|
        next unless sides[:command_name] && sides[:launching_text]
        next if sides[:command_name] == sides[:launching_text]

        { tool_use_id: tool_use_id, command_name: sides[:command_name], launching_text: sides[:launching_text] }
      end
      matched = state[:corroboration_by_id].count { |_, sides| sides[:command_name] }

      Result.new(
        files_top: state[:files_top], files_subagent: state[:files_subagent],
        record_count: state[:record_count], unparsable_lines: state[:unparsable_lines],
        first_seen: state[:first_seen], last_seen: state[:last_seen],
        calls_main: state[:calls_main], calls_agent: state[:calls_agent], other_skills: state[:other_skills],
        loads: state[:loads], attributed: state[:attributed], mentions: state[:mentions],
        scripts: state[:scripts], agents: state[:agents],
        transcript_typed: state[:transcript_typed], self_generated: state[:self_generated],
        corroboration: Corroboration.new(matched: matched, disagreements: disagreements),
        self_generated_calls: state[:self_generated_calls], self_generated_loads: state[:self_generated_loads],
        self_generated_attributed: state[:self_generated_attributed],
        self_generated_mentions: state[:self_generated_mentions]
      )
    end

    def plastic_name?(name)
      name.start_with?("plastic-")
    end

    def subagent_path?(path)
      path.split(File::SEPARATOR).include?("subagents")
    end

    def iso_to_date(value)
      return nil if value.nil?

      Time.parse(value.to_s).to_date
    rescue ArgumentError, TypeError
      nil
    end

    def message_content(record)
      record["message"].is_a?(Hash) ? record["message"]["content"] : record["content"]
    end

    def each_content_block(record)
      content = message_content(record)
      return unless content.is_a?(Array)

      content.each { |block| yield block }
    end

    def extract_text(record)
      content = message_content(record)
      return content if content.is_a?(String)
      return nil unless content.is_a?(Array)

      content.filter_map { |b| b["text"] if b.is_a?(Hash) && b["type"] == "text" }.join("\n")
    end

    def load_name_from(text)
      return nil unless text.lstrip.start_with?(LOAD_PREFIX)

      path = text.lstrip.sub(LOAD_PREFIX, "").strip.lines.first.to_s.strip
      File.basename(path)
    end

    def tagged_or_bare_typed_name(text)
      if (m = text.match(PLASTIC_TAGGED_RE))
        return SkillCensus.normalize(m[1])
      end
      if (m = text.match(PLASTIC_TYPED_RE))
        return SkillCensus.normalize(m[1])
      end

      nil
    end
  end

  # -------------------------------------------------------------------
  # Tally - maps both sources' events onto the roster through NAME_MAP,
  # RETIRED, and MECHANISMS.
  # -------------------------------------------------------------------
  class Tally
    SkillRow = Struct.new(
      :name, :user_invocable, :typed, :calls_main, :calls_agent, :loads,
      :attributed, :mapped_from, :mechanism, :first_seen, :last_seen,
      keyword_init: true
    ) do
      def evidence?
        typed.to_i.positive? || calls_main.to_i.positive? || calls_agent.to_i.positive?
      end
    end

    Built = Struct.new(:skills, :retired, :unmapped, :map_coverage, :history, :transcript, keyword_init: true)

    def initialize(history_scan, transcript_scan, roster, name_map: NAME_MAP)
      @name_map = name_map
      @history = history_scan
      @transcript = transcript_scan
      @roster = roster
    end

    def build
      rows = {}
      @roster.each { |skill| rows[skill.name] = new_row(skill) }
      retired_row = new_row(nil, name: "retired")
      unmapped_row = new_row(nil, name: "unmapped")

      apply = lambda do |raw_name, field, date = nil|
        target = resolve(raw_name, rows)
        row = case target
              when :retired then retired_row
              when :unmapped then unmapped_row
              else rows[target]
              end
        row[field] += 1
        row.mapped_from[raw_name] += 1 if target != raw_name
        track_row_span(row, date)
      end

      @history.typed.each { |event| apply.call(event.name, :typed, event.date) }
      @transcript.calls_main.each { |call| apply.call(call.name, :calls_main, call.date) }
      @transcript.calls_agent.each { |call| apply.call(call.name, :calls_agent, call.date) }
      @transcript.loads.each { |event| apply.call(event.name, :loads, event.date) }
      @transcript.attributed.each { |name, count| count.times { apply.call(name, :attributed) } }

      map_coverage = @name_map.map do |raw, target|
        { raw: raw, target: target, observed: rows[target]&.mapped_from&.fetch(raw, 0) || 0 }
      end

      Built.new(skills: @roster.map { |s| rows[s.name] }, retired: retired_row, unmapped: unmapped_row,
                map_coverage: map_coverage, history: @history, transcript: @transcript)
    end

    private

    def new_row(skill, name: nil)
      SkillRow.new(
        name: skill&.name || name, user_invocable: skill&.user_invocable,
        typed: 0, calls_main: 0, calls_agent: 0, loads: 0, attributed: 0,
        mapped_from: Hash.new(0), mechanism: skill && MECHANISMS[skill.name]
      )
    end

    def resolve(raw_name, rows)
      return raw_name if rows.key?(raw_name)

      target = @name_map[raw_name]
      return target if target && rows.key?(target)
      return :retired if RETIRED.include?(raw_name)

      :unmapped
    end

    def track_row_span(row, date)
      return unless date

      row.first_seen = date if row.first_seen.nil? || date < row.first_seen
      row.last_seen = date if row.last_seen.nil? || date > row.last_seen
    end
  end

  # -------------------------------------------------------------------
  # Report - Markdown and JSON rendering.
  # -------------------------------------------------------------------
  module Report
    module_function

    def markdown(built, history_path: nil, transcripts_path: nil, cutoff: nil)
      lines = []
      lines.concat(header(history_path, transcripts_path, cutoff))
      lines.concat(method_section(cutoff))
      lines.concat(summary_table(built))
      lines.concat(per_skill_sections(built))
      lines.concat(context_tables(built))
      lines.concat(cross_check_section(built))
      lines.concat(self_generated_section(built))
      lines.concat(typed_events_section(built))
      lines.join("\n") + "\n"
    end

    def header(history_path, transcripts_path, cutoff)
      lines = ["# Plastic skill usage census", ""]
      lines << "- history: #{history_path}" if history_path
      lines << "- transcripts: #{transcripts_path}" if transcripts_path
      lines << "- cutoff: #{cutoff}" if cutoff
      lines << ""
      lines
    end

    def method_section(cutoff)
      [
        "## Method",
        "",
        "- Typed command: a history.jsonl record whose display matches a leading /plastic- or /plastic: form; " \
        "a mid-sentence or backticked mention is excluded and tallied separately.",
        "- Calls: a Skill tool_use block, split into calls_main (top-level transcript file) and calls_agent " \
        "(subagent transcript file), because the auto pipeline dispatches its own skills.",
        "- Loads: a user record whose text begins \"Base directory for this skill:\".",
        "- Attribution: attributionSkill on a record measures time spent under a skill, not invocations, and " \
        "never feeds the call count.",
        "- Cutoff: records dated on or after #{cutoff} are excluded from every count and reported on the " \
        "Self-generated line.",
        "",
      ]
    end

    def summary_table(built)
      lines = [
        "## Summary",
        "",
        "| skill | user_invocable | typed | calls_main | calls_agent | loads | attributed | evidence |",
        "| --- | --- | --- | --- | --- | --- | --- | --- |",
      ]
      (built.skills + [built.retired, built.unmapped]).each { |row| lines << summary_row(row) }
      lines << ""
      lines
    end

    def summary_row(row)
      if row.mechanism && !row.evidence?
        "| #{row.name} | #{fmt(row.user_invocable)} | n/a | n/a | n/a | #{row.loads} | #{row.attributed} | n/a - #{row.mechanism} |"
      else
        "| #{row.name} | #{fmt(row.user_invocable)} | #{row.typed} | #{row.calls_main} | #{row.calls_agent} | " \
        "#{row.loads} | #{row.attributed} | #{row.evidence? ? "measured" : "zero"} |"
      end
    end

    def fmt(value)
      value.nil? ? "-" : value.to_s
    end

    def per_skill_sections(built)
      lines = ["## Per-skill", ""]
      built.skills.each do |row|
        lines << "## #{row.name}"
        lines << ""
        lines << "| field | value |"
        lines << "| --- | --- |"
        if row.mechanism && !row.evidence?
          lines << "| evidence | n/a |"
          lines << "| mechanism | #{row.mechanism} |"
        else
          lines << "| typed | #{row.typed} |"
          lines << "| calls_main | #{row.calls_main} |"
          lines << "| calls_agent | #{row.calls_agent} |"
        end
        lines << "| loads | #{row.loads} |"
        lines << "| attributed | #{row.attributed} (time spent under this skill, not invocations) |"
        unless row.mapped_from.empty?
          mapped = row.mapped_from.map { |name, count| "#{name} (#{count})" }.join(", ")
          lines << "| mapped from | #{mapped} |"
        end
        lines << "| first seen | #{row.first_seen} |" if row.first_seen
        lines << "| last seen | #{row.last_seen} |" if row.last_seen
        lines << ""
      end
      lines
    end

    def context_tables(built)
      transcript = built.transcript
      history = built.history
      lines = ["## Built-in commands", "", "| command | count |", "| --- | --- |"]
      history.builtins.sort.each { |name, count| lines << "| /#{name} | #{count} |" }
      lines << ""

      lines << "## Other skills"
      lines << ""
      lines << "| skill | calls | loads | attributed |"
      lines << "| --- | --- | --- | --- |"
      transcript.other_skills.sort.each do |name, counts|
        lines << "| #{name} | #{counts[:calls]} | #{counts[:loads]} | #{counts[:attributed]} |"
      end
      lines << ""

      lines << "## Scripts"
      lines << ""
      lines << "| script | occurrences |"
      lines << "| --- | --- |"
      SCRIPTS.each { |name| lines << "| #{name} | #{transcript.scripts.fetch(name, 0)} |" }
      lines << ""

      lines << "## Agents"
      lines << ""
      lines << "| agent | occurrences |"
      lines << "| --- | --- |"
      AGENTS.each { |name| lines << "| #{name} | #{transcript.agents.fetch(name, 0)} |" }
      lines << ""

      lines << "## Map coverage"
      lines << ""
      lines << "| raw name | maps to | observed |"
      lines << "| --- | --- | --- |"
      built.map_coverage.each { |entry| lines << "| #{entry[:raw]} | #{entry[:target]} | #{entry[:observed]} |" }
      lines << ""
      lines << "Observed sums typed, calls (main plus agent), loads, and attributed occurrences for " \
      "that raw name; it is not a single dimension."
      lines << ""
      lines
    end

    def cross_check_section(built)
      history = built.history
      transcript = built.transcript
      window_start = transcript.first_seen
      history_in_window = if window_start
                            history.typed.count { |e| e.date && e.date >= window_start }
                          else
                            0
                          end
      transcript_typed_total = transcript.transcript_typed.length
      gap = history_in_window.zero? ? 0 : ((history_in_window - transcript_typed_total).abs.to_f / history_in_window * 100).round(1)

      [
        "## Cross-check",
        "",
        "History typed commands inside the transcript window (from #{window_start}): #{history_in_window}.",
        "Transcript-typed events over the same window: #{transcript_typed_total}.",
        "Gap: #{gap} percent.",
        "",
      ]
    end

    def self_generated_section(built)
      history_self = built.history.self_generated
      transcript = built.transcript
      [
        "## Self-generated",
        "",
        "History records excluded by the cutoff: #{history_self.length}.",
        "",
        "Transcript records excluded by the cutoff, per dimension (D16: the cutoff gates " \
        "every count, not only typed commands):",
        "",
        "| dimension | excluded |",
        "| --- | --- |",
        "| typed | #{transcript.self_generated.length} |",
        "| mentions | #{transcript.self_generated_mentions.to_i} |",
        "| calls | #{transcript.self_generated_calls.to_i} |",
        "| loads | #{transcript.self_generated_loads.to_i} |",
        "| attributed | #{transcript.self_generated_attributed.to_i} |",
        "",
      ]
    end

    def typed_events_section(built)
      lines = ["## Typed events", "", "| name | date | project |", "| --- | --- | --- |"]
      built.history.typed.each { |event| lines << "| #{event.name} | #{event.date} | #{event.project} |" }
      lines << ""
      lines
    end

    def json(built, history_path: nil, transcripts_path: nil, cutoff: nil)
      JSON.pretty_generate(build_data(built, history_path: history_path, transcripts_path: transcripts_path, cutoff: cutoff))
    end

    def build_data(built, history_path: nil, transcripts_path: nil, cutoff: nil)
      {
        "history_path" => history_path,
        "transcripts_path" => transcripts_path,
        "cutoff" => cutoff,
        "skills" => (built.skills + [built.retired, built.unmapped]).map { |row| row_data(row) },
        "map_coverage" => built.map_coverage,
        "history" => {
          "record_count" => built.history.record_count,
          "first_seen" => built.history.first_seen&.to_s,
          "last_seen" => built.history.last_seen&.to_s,
          "typed_total" => built.history.typed.length,
          "monthly" => built.history.monthly,
          "builtins" => built.history.builtins,
          "self_generated" => built.history.self_generated.length,
        },
        "transcript" => {
          "files_top" => built.transcript.files_top,
          "files_subagent" => built.transcript.files_subagent,
          "record_count" => built.transcript.record_count,
          "unparsable_lines" => built.transcript.unparsable_lines,
          "first_seen" => built.transcript.first_seen&.to_s,
          "last_seen" => built.transcript.last_seen&.to_s,
          "calls_main" => built.transcript.calls_main.length,
          "calls_agent" => built.transcript.calls_agent.length,
          "other_skills" => built.transcript.other_skills,
          "loads" => built.transcript.loads.length,
          "attributed" => built.transcript.attributed,
          "mentions" => built.transcript.mentions.length,
          "scripts" => built.transcript.scripts,
          "agents" => built.transcript.agents,
          "transcript_typed" => built.transcript.transcript_typed.length,
          "self_generated" => built.transcript.self_generated.length,
          "self_generated_mentions" => built.transcript.self_generated_mentions.to_i,
          "self_generated_calls" => built.transcript.self_generated_calls.to_i,
          "self_generated_loads" => built.transcript.self_generated_loads.to_i,
          "self_generated_attributed" => built.transcript.self_generated_attributed.to_i,
          "corroboration_matched" => built.transcript.corroboration.matched,
          "corroboration_disagreements" => built.transcript.corroboration.disagreements,
        },
      }
    end

    def row_data(row)
      {
        "name" => row.name, "user_invocable" => row.user_invocable,
        "typed" => row.typed, "calls_main" => row.calls_main, "calls_agent" => row.calls_agent,
        "loads" => row.loads, "attributed" => row.attributed,
        "mapped_from" => row.mapped_from, "mechanism" => row.mechanism,
        "first_seen" => row.first_seen&.to_s, "last_seen" => row.last_seen&.to_s,
      }
    end
  end
end
