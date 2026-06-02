#!/usr/bin/env ruby
# encoding: UTF-8

require "json"
require "fileutils"
require "tempfile"

module Bridge
  STAGES = %w[what why how exec done].freeze

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
    return "why" if File.exist?("#{intent_dir}/intent.md")
    "what"
  end

  def self.has_files(intent_dir)
    files = []
    %w[intent.md spec.md plan.md checklist.md outcome.md].each do |f|
      files << f if File.exist?("#{intent_dir}/#{f}")
    end
    files << "actions/" if File.directory?("#{intent_dir}/actions")
    files
  end

  def self.missing_for_stage(stage)
    case stage
    when "what" then ["intent.md"]
    when "why" then ["spec.md"]
    when "how" then ["plan.md", "actions/", "checklist.md"]
    when "exec" then ["outcome.md"]
    else []
    end
  end

  def self.derive(session, intent_id:, intent_dir:, store:, name:)
    stage = derive_stage(intent_dir)
    has = has_files(intent_dir)
    missing = missing_for_stage(stage) - has

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
      intent_file = "#{intent_dir}/intent.md"
      unless File.exist?(intent_file) && File.read(intent_file).include?("## Intent")
        return "Cannot start Why — What is incomplete (intent.md missing or no ## Intent)"
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
end
