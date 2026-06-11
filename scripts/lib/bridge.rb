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
