#!/usr/bin/env ruby
# encoding: UTF-8

require "json"
require "yaml"
require "fileutils"
require "tempfile"

module Bridge
  STAGES = %w[what why how exec done].freeze

  def self.intent_file(intent_dir)
    dir_name = File.basename(intent_dir)
    "#{intent_dir}/#{dir_name}.md"
  end

  def self.path(session)
    "/tmp/plastic-#{session}.json"
  end

  def self.read(session)
    p = path(session)
    return nil unless File.exist?(p)
    JSON.parse(File.read(p))
  rescue JSON::ParserError
    nil
  end

  def self.write(session, data)
    p = path(session)
    # Atomic write: tmp file + rename to prevent partial reads
    tmp = "#{p}.tmp.#{Process.pid}"
    File.write(tmp, JSON.pretty_generate(data.merge("updated_at" => Time.now.utc.iso8601)))
    File.rename(tmp, p)
  rescue => e
    File.delete(tmp) if tmp && File.exist?(tmp)
    raise e
  end

  def self.derive_stage(intent_dir)
    return "done" if File.exist?("#{intent_dir}/outcome.md")
    if File.exist?("#{intent_dir}/plan.md") &&
       File.directory?("#{intent_dir}/actions") &&
       File.exist?("#{intent_dir}/checklist.md")
      return "exec"
    end
    return "how" if File.exist?("#{intent_dir}/spec.md")
    return "why" if File.exist?(intent_file(intent_dir))
    "what"
  end

  def self.has_files(intent_dir)
    files = []
    ifile = File.basename(intent_file(intent_dir))
    [ifile, "spec.md", "plan.md", "checklist.md", "outcome.md"].each do |f|
      files << f if File.exist?("#{intent_dir}/#{f}")
    end
    files << "actions/" if File.directory?("#{intent_dir}/actions")
    files
  end

  def self.missing_for_stage(stage, intent_dir = nil)
    ifile = intent_dir ? File.basename(intent_file(intent_dir)) : "intent.md"
    case stage
    when "what" then [ifile]
    when "why" then ["spec.md"]
    when "how" then ["plan.md", "actions/", "checklist.md"]
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

  # Append a milestone line for file_path if (and only if) it is a milestone
  # not already recorded. Returns true when a line was written, false otherwise.
  def self.append_savepoint(intent_dir, file_path, now: Time.now)
    stage, milestone = savepoint_milestone(intent_dir, File.basename(file_path))
    return false unless milestone
    return false if savepoint_recorded_milestones(intent_dir).include?(milestone)

    line = "#{now.utc.iso8601}  #{stage}  #{milestone}\n"
    File.open(File.join(intent_dir, SAVEPOINT_FILE), "a") { |io| io.write(line) }
    true
  end

  # Reconstruct the ledger from files on disk (timestamps from mtimes), in
  # stage order, overwriting savepoint.md. Returns the number of lines written.
  def self.rebuild_savepoint(intent_dir)
    ordered = [
      File.basename(intent_file(intent_dir)),
      "spec.md", "plan.md", "checklist.md", "outcome.md",
    ]
    lines = ordered.filter_map do |basename|
      path = File.join(intent_dir, basename)
      next unless File.exist?(path)
      stage, milestone = savepoint_milestone(intent_dir, basename)
      next unless milestone
      "#{File.mtime(path).utc.iso8601}  #{stage}  #{milestone}\n"
    end
    File.write(File.join(intent_dir, SAVEPOINT_FILE), lines.join)
    lines.length
  end

  def self.derive(session, intent_id:, intent_dir:, store:, name:)
    stage = derive_stage(intent_dir)
    has = has_files(intent_dir)
    missing = missing_for_stage(stage, intent_dir) - has

    data = {
      "session" => session,
      "intent" => {
        "id" => intent_id,
        "dir" => intent_dir.sub("#{store}/", ""),
        "store" => store,
        "name" => name
      },
      "build" => {
        "stage" => stage,
        "has" => has,
        "missing" => missing,
        "gate_failures" => 0,
        "auto" => false,
        "last_activity" => Time.now.utc.iso8601
      },
      "observe" => {
        "last_transition" => nil,
        "insights_count" => 0,
        "chain_spawned" => []
      },
      "tokens" => {
        "context_pct" => 0,
        "warning_at" => 80,
        "critical_at" => 90
      }
    }

    write(session, data)
    data
  end

  # Gate check: returns nil if allowed, or an error message string if blocked
  def self.check_gate(intent_dir, file_being_written)
    basename = File.basename(file_being_written)

    case basename
    when "spec.md"
      ifile = intent_file(intent_dir)
      unless File.exist?(ifile) && File.read(ifile).include?("## Intent")
        return "Cannot start Why — What is incomplete (#{File.basename(ifile)} missing or no ## Intent)"
      end
    when "plan.md"
      unless File.exist?("#{intent_dir}/spec.md")
        return "Cannot start How — Why is incomplete (spec.md missing)"
      end
    when "checklist.md"
      unless File.exist?("#{intent_dir}/plan.md") && File.directory?("#{intent_dir}/actions")
        return "Cannot complete How — plan.md or actions/ missing"
      end
    when "outcome.md"
      checklist = "#{intent_dir}/checklist.md"
      if File.exist?(checklist)
        content = File.read(checklist)
        unchecked = content.scan(/^- \[ \]/).length
        if unchecked > 0
          return "Cannot complete Exec — #{unchecked} unchecked items in checklist.md"
        end
      end
    end

    nil # no gate violation
  end

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

  # --- Auto mode (intent 27) ---

  # Arm auto mode for a session+intent. Works even when no bridge exists yet
  # (mid-session intent creation). Re-derives intent state, then sets build.auto.
  def self.arm_auto(session, intent_id:, intent_dir:, store:, name:)
    data = derive(session, intent_id: intent_id, intent_dir: intent_dir, store: store, name: name)
    data["build"]["auto"] = true
    write(session, data)
    data
  end

  # Disarm auto mode. No-op if no bridge exists for the session.
  def self.disarm_auto(session)
    data = read(session)
    return nil unless data
    data["build"] ||= {}
    data["build"]["auto"] = false
    write(session, data)
    data
  end

  # Decide whether a code edit should be blocked while auto mode is armed.
  # Returns a reason string to BLOCK, or nil to ALLOW.
  #
  # Blocks iff: auto armed AND intent hasn't reached How (stage what/why) AND the
  # target is project code — i.e. NOT under ~/.plastic and NOT inside the intent dir.
  def self.code_gate_decision(bridge_data, file_path, home: Dir.home)
    return nil unless bridge_data.is_a?(Hash)
    build = bridge_data["build"] || {}
    return nil unless build["auto"] == true

    intent_info = bridge_data["intent"] || {}
    store = intent_info["store"]
    dir = intent_info["dir"]
    return nil unless store && dir
    intent_dir_abs = File.expand_path("#{store}/#{dir}")

    # "How reached" = the plan triplet exists. Gate by artifact presence, not the
    # stage label (derive_stage returns "how" as soon as spec.md exists, before any
    # plan). Code edits stay blocked until plan.md + checklist.md are both present.
    reached_how = File.exist?("#{intent_dir_abs}/plan.md") &&
                  File.exist?("#{intent_dir_abs}/checklist.md")
    return nil if reached_how

    file_abs = File.expand_path(file_path.to_s)
    plastic_home = File.expand_path(File.join(home, ".plastic"))
    return nil if file_abs == plastic_home || file_abs.start_with?("#{plastic_home}/")
    return nil if file_abs == intent_dir_abs || file_abs.start_with?("#{intent_dir_abs}/")

    id = intent_info["id"]
    "intent #{id} has not reached How — write plan.md + checklist.md before " \
      "editing project code. Run plastic-auto or plastic-writing-plans first. " \
      "(blocked edit: #{file_abs})"
  end

  # --- Bash-edit gate (intent 27a) ---

  # Extract the set of file paths a Bash command writes to. Conservative by
  # design: it is acceptable to miss exotic forms, but it must NOT flag reads
  # or /dev/null. Returns an Array of path strings (possibly relative).
  #
  # Covered write vectors: redirection (>, >>, including heredoc `cat > f <<EOF`),
  # tee / tee -a, sed -i / sed -i.bak, cp/mv (last non-flag arg), dd of=.
  def self.bash_write_targets(command)
    return [] unless command.is_a?(String)

    targets = []
    targets.concat(bash_redirect_targets(command))
    # Split on command separators for per-segment utility parsing.
    command.split(/[;\n]|&&|\|\||\|/).each do |segment|
      targets.concat(bash_utility_targets(segment))
    end
    targets.uniq
  end

  # Redirections: `> path` / `>> path`, but not fd dups (`2>&1`) or /dev/null.
  # A leading digit (fd number) before > is fine; `>&` is a dup and excluded.
  def self.bash_redirect_targets(command)
    targets = []
    # Match optional leading fd digits, then > or >>, not followed by & , then path.
    command.scan(/\d*>>?(?!&)\s*([^\s;|&<>]+)/) do |m|
      path = m[0]
      next if path.nil? || path.empty?
      next if dev_null?(path)
      targets << path
    end
    targets
  end

  def self.bash_utility_targets(segment)
    tokens = segment.strip.split(/\s+/)
    return [] if tokens.empty?

    # Find the utility name, skipping env-style assignments.
    idx = 0
    idx += 1 while tokens[idx] && tokens[idx].include?("=") && tokens[idx] !~ /^-/ && !tokens[idx].start_with?("of=")
    util = File.basename(tokens[idx].to_s)
    args = tokens[(idx + 1)..] || []

    case util
    when "tee"
      tee_targets(args)
    when "sed"
      sed_targets(args)
    when "cp", "mv"
      copy_move_targets(args)
    when "dd"
      dd_targets(tokens)
    else
      []
    end
  end

  def self.tee_targets(args)
    args.reject { |a| a.start_with?("-") || dev_null?(a) }
  end

  def self.sed_targets(args)
    # In-place only: -i or -i.bak (suffix attached). Otherwise sed reads.
    inplace = args.any? { |a| a == "-i" || a.start_with?("-i") }
    return [] unless inplace
    files = args.reject { |a| a.start_with?("-") }
    # sed args: script then file(s). First non-flag is the script expression
    # unless an -e/-f was used; conservatively treat the LAST non-flag as file.
    files.empty? ? [] : [files.last].reject { |f| dev_null?(f) }
  end

  def self.copy_move_targets(args)
    files = args.reject { |a| a.start_with?("-") }
    return [] if files.length < 2
    dest = files.last
    dev_null?(dest) ? [] : [dest]
  end

  def self.dd_targets(tokens)
    tokens.each_with_object([]) do |t, acc|
      next unless t.start_with?("of=")
      path = t.sub("of=", "")
      acc << path unless path.empty? || dev_null?(path)
    end
  end

  def self.dev_null?(path)
    path == "/dev/null" || path.start_with?("/dev/")
  end

  # Decide whether a Bash command should be blocked under the auto-mode code
  # gate. Resolves each write target against cwd and applies the SAME policy as
  # code_gate_decision. Returns the first block reason, or nil to allow.
  def self.bash_gate_decision(bridge_data, command, cwd:, home: Dir.home)
    bash_write_targets(command).each do |target|
      abs = File.absolute_path?(target) ? target : File.join(cwd, target)
      reason = code_gate_decision(bridge_data, abs, home: home)
      return reason if reason
    end
    nil
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
