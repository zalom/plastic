# encoding: UTF-8
# frozen_string_literal: true

require "json"
require "time"

# SessionUsage (intent 355, D10): reads the harness transcripts modified since
# a cutoff, dedupes assistant records by message id (the harness logs one
# record per content block), and reports per session the model, the calls in
# the window, the boot and last context, the median step, the steps over 5k,
# and the cache read. Context is input plus cache read plus cache write.
# Broken records are counted and named, never averaged over. The transcripts
# root and the rate-limit cache path are injected; nothing reads ENV.
class SessionUsage
  WINDOW = 5 * 3600
  BIG_STEP = 5_000
  LABEL_WIDTH = 70
  NO_PROMPT = "(no prompt)"
  SYNTHETIC_MODEL = "<synthetic>"
  CONTEXT_FIELDS = %w[input_tokens cache_read_input_tokens cache_creation_input_tokens].freeze
  TRANSCRIPT_GLOBS = [File.join("*", "*.jsonl"), File.join("*", "*", "subagents", "*.jsonl")].freeze
  HEADERS = ["session", "model", "calls", "boot", "last", "median step", "big steps", "cache read", "broken", "prompt"].freeze

  def initialize(transcripts_root:, rate_limits_path:, now: Time.now)
    @transcripts_root = transcripts_root
    @rate_limits_path = rate_limits_path
    @now = now
  end

  def cutoff(since: nil)
    return [since, "since"] if since

    reset = reset_time
    return [reset - WINDOW, "rate-limit reset"] if reset && reset > @now

    [@now - WINDOW, "last 5 hours"]
  end

  def report(since: nil)
    at, source = cutoff(since: since)
    header = { "status" => "ok", "root" => @transcripts_root, "cutoff" => at.getutc.iso8601, "cutoff_source" => source }
    return header.merge("status" => "unavailable") unless File.directory?(@transcripts_root)

    broken = []
    sessions = transcripts(at).filter_map { |path| summarize(path, at, broken) }
    header.merge("sessions" => sessions.sort_by { |s| -s["cache_read"] }, "broken" => broken)
  end

  def self.render_text(report)
    return "Session usage: unavailable (no transcripts directory at #{report['root']})\n" if report["status"] == "unavailable"

    out = +"Session usage since #{report['cutoff']} (#{report['cutoff_source']})\n\n"
    out << (report["sessions"].empty? ? "(no sessions)\n" : table(report["sessions"]))
    return out if report["broken"].empty?

    out << "\nBroken records (#{report['broken'].size}):\n"
    report["broken"].each { |b| out << "  #{b['file']}:#{b['line']}  #{b['error']}\n" }
    out
  end

  def self.table(sessions)
    rows = sessions.map do |s|
      boot = tokens(s["boot"]) + (s["started_before_cutoff"] ? "*" : "")
      [s["id"], s["model"].to_s, s["calls"].to_s, boot, tokens(s["last"]), tokens(s["median_step"]),
       s["big_steps"].to_s, tokens(s["cache_read"]), s["broken"].to_s, s["label"]]
    end
    widths = HEADERS.each_index.map { |i| ([HEADERS] + rows).map { |r| r[i].length }.max }
    lines = ([HEADERS] + rows).map { |r| r.each_with_index.map { |cell, i| cell.ljust(widths[i]) }.join("  ").rstrip }
    note = sessions.any? { |s| s["started_before_cutoff"] } ? "\n* boot predates the cutoff\n" : ""
    lines.join("\n") + "\n" + note
  end

  def self.tokens(count)
    return "-" if count.nil?

    count.abs >= 1_000 ? format("%.1fk", count / 1_000.0) : count.to_s
  end

  private_class_method :table, :tokens

  private

  def reset_time
    return unless File.file?(@rate_limits_path)

    value = JSON.parse(File.read(@rate_limits_path))["resets_at"].to_s
    return if value.empty?

    value.match?(/\A\d+\z/) ? Time.at(value.to_i).utc : Time.iso8601(value)
  rescue JSON::ParserError, ArgumentError, TypeError
    nil
  end

  def transcripts(cutoff)
    TRANSCRIPT_GLOBS.flat_map { |glob| Dir.glob(File.join(@transcripts_root, glob)) }
                    .select { |path| File.mtime(path) >= cutoff }
                    .sort
  end

  def summarize(path, cutoff, broken)
    calls = {}
    label = nil
    torn = 0
    File.foreach(path).with_index(1) do |line, number|
      next if line.strip.empty?

      record = JSON.parse(line)
      raise TypeError, "record is not a JSON object" unless record.is_a?(Hash)

      label ||= prompt_line(record)
      call = call_from(record)
      next unless call

      calls[call[:id]] = calls.key?(call[:id]) ? call.merge(at: calls[call[:id]][:at]) : call
    rescue JSON::ParserError
      torn += 1
      broken << { "file" => path, "line" => number, "error" => "unparsable JSON" }
    rescue ArgumentError, TypeError => e
      torn += 1
      broken << { "file" => path, "line" => number, "error" => e.message }
    end
    row(path, calls.values, cutoff, label, torn)
  end

  def row(path, calls, cutoff, label, torn)
    window = calls.each_index.select { |i| calls[i][:at] >= cutoff }
    return if window.empty? && torn.zero?

    steps = window.filter_map { |i| calls[i][:context] - calls[i - 1][:context] if i.positive? }
    {
      "id" => File.basename(path, ".jsonl"),
      "file" => path,
      "label" => label || NO_PROMPT,
      "model" => calls.last && calls.last[:model],
      "calls" => window.size,
      "boot" => calls.first && calls.first[:context],
      "last" => calls.last && calls.last[:context],
      "median_step" => median(steps),
      "big_steps" => steps.count { |step| step > BIG_STEP },
      "cache_read" => window.sum { |i| calls[i][:cache_read] },
      "broken" => torn,
      "started_before_cutoff" => !calls.empty? && calls.first[:at] < cutoff,
    }
  end

  def call_from(record)
    return unless record["type"] == "assistant"

    message = record["message"]
    raise TypeError, "assistant record without a message" unless message.is_a?(Hash)
    return if message["model"] == SYNTHETIC_MODEL

    usage = message["usage"]
    raise ArgumentError, "assistant record without message id or usage" unless message["id"] && usage.is_a?(Hash)

    {
      id: message["id"],
      model: message["model"],
      at: Time.iso8601(record["timestamp"].to_s),
      context: CONTEXT_FIELDS.sum { |field| usage[field].to_i },
      cache_read: usage["cache_read_input_tokens"].to_i,
    }
  end

  def prompt_line(record)
    return unless record["type"] == "user" && !record["isMeta"]

    text = prompt_text(record["message"].is_a?(Hash) ? record["message"]["content"] : nil)
    return if text.nil?

    first = text.lines.map(&:strip).find { |line| !line.empty? && !line.start_with?("<") }
    first && first[0, LABEL_WIDTH]
  end

  def prompt_text(content)
    return content if content.is_a?(String)
    return unless content.is_a?(Array)

    block = content.find { |b| b.is_a?(Hash) && b["type"] == "text" }
    block && block["text"]
  end

  def median(values)
    return if values.empty?

    sorted = values.sort
    middle = sorted.size / 2
    sorted.size.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
  end
end
