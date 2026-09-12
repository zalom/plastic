# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"
require "time"
require_relative "../scripts/lib/session_usage"

# Intent 355, n1: session-usage reads the harness transcripts and reports per
# session the context each call carried. Every path is injected, nothing reads ENV.
class SessionUsageTest < Minitest::Test
  FIXTURE_ROOT = File.expand_path("fixtures/transcripts", __dir__)
  FIXTURE_RECORDS = Dir.glob(File.join(FIXTURE_ROOT, "**", "*.jsonl")).flat_map do |file|
    File.readlines(file).map { |line| JSON.parse(line) }
  end
  NOW = Time.utc(2026, 9, 12, 10, 0, 0)

  def setup
    @home = Dir.mktmpdir("session-usage")
    @root = File.join(@home, "projects")
    @rate_limits = File.join(@home, "rate-limits.json")
    FileUtils.mkdir_p(@root)
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def call(id, at:, input: 0, cache_write: 0, cache_read: 0, model: "claude-opus-5")
    record = JSON.parse(JSON.generate(FIXTURE_RECORDS.first))
    record["message"].merge!("id" => id, "model" => model)
    record["message"]["usage"].merge!("input_tokens" => input,
                                      "cache_creation_input_tokens" => cache_write,
                                      "cache_read_input_tokens" => cache_read)
    record["timestamp"] = at.utc.iso8601(3)
    record
  end

  def prompt(content, at: NOW - 3600, meta: false)
    record = { "type" => "user", "message" => { "role" => "user", "content" => content },
               "timestamp" => at.utc.iso8601(3), "sessionId" => "fixture" }
    meta ? record.merge("isMeta" => true) : record
  end

  def write_transcript(relative, records)
    path = File.join(@root, "-tmp-project", "#{relative}.jsonl")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, records.map { |r| r.is_a?(String) ? r : JSON.generate(r) }.join("\n") + "\n")
    path
  end

  def usage(root: @root)
    SessionUsage.new(transcripts_root: root, rate_limits_path: @rate_limits, now: NOW)
  end

  def session(report, id)
    report["sessions"].find { |s| s["id"] == id } || flunk("no session #{id} in #{report['sessions'].map { |s| s['id'] }}")
  end

  def at(hour, minute = 0)
    Time.utc(2026, 9, 12, hour, minute, 0)
  end

  def test_records_deduped_by_message_id
    FileUtils.cp_r(File.join(FIXTURE_ROOT, "."), @root)
    report = usage.report(since: at(0))
    row = session(report, "agent-afixture00000001")
    assert_equal 2, row["calls"]
    assert_equal 2 + 44_651, row["boot"]
    assert_equal 32 + 4_481 + 44_651, row["last"]
    assert_equal 44_651, row["cache_read"]
  end

  def test_context_sums_all_three_input_fields
    write_transcript("sums", [call("m1", at: at(7), input: 10, cache_write: 200, cache_read: 3_000)])
    row = session(usage.report(since: at(6)), "sums")
    assert_equal 3_210, row["boot"]
    assert_equal 3_210, row["last"]
    assert_equal 3_000, row["cache_read"]
  end

  def test_boot_and_last_are_first_and_final_calls
    write_transcript("long", [call("m1", at: at(1), cache_read: 40_000),
                              call("m2", at: at(7), cache_read: 400_000),
                              call("m3", at: at(8), cache_read: 434_000)])
    row = session(usage.report(since: at(6)), "long")
    assert_equal 40_000, row["boot"]
    assert_equal 434_000, row["last"]
    assert_equal 2, row["calls"]
    assert_equal true, row["started_before_cutoff"]
  end

  def test_median_step_and_big_step_count
    contexts = [10_000, 11_000, 12_000, 20_000, 21_000]
    write_transcript("steps", contexts.each_with_index.map { |c, i| call("m#{i}", at: at(7, i), cache_read: c) })
    row = session(usage.report(since: at(6)), "steps")
    assert_equal 1_000, row["median_step"]
    assert_equal 1, row["big_steps"]
  end

  def test_session_labelled_by_first_prompt_and_model
    write_transcript("lead", [prompt("<local-command-caveat>Caveat: generated</local-command-caveat>", meta: true),
                              prompt("<command-name>/clear</command-name>"),
                              prompt("\nRun node n1 of intent 355\nsecond line"),
                              call("m1", at: at(7), input: 5),
                              call("m2", at: at(7, 1), input: 0, model: "<synthetic>")])
    write_transcript("lead/subagents/agent-aexec", [prompt([{ "type" => "text", "text" => "Execute the packet" }]),
                                                    call("m1", at: at(7), input: 5, model: "claude-sonnet-5")])
write_transcript("lead/subagents/agent-alead-355-1",
                 [prompt(%(<teammate-message teammate_id="main" summary="Lead n1">\nLead intent 355 node n1\nmore\n</teammate-message>)),
                  call("m1", at: at(7), input: 5)])
    report = usage.report(since: at(6))
    lead = session(report, "lead")
    assert_equal "Run node n1 of intent 355", lead["label"]
    assert_equal "claude-opus-5", lead["model"]
    assert_equal 1, lead["calls"]
    executor = session(report, "agent-aexec")
    assert_equal "Execute the packet", executor["label"]
    assert_equal "claude-sonnet-5", executor["model"]
    assert_equal "Lead intent 355 node n1", session(report, "agent-alead-355-1")["label"]
  end

  def test_cutoff_from_flag_or_reset_time
    write_transcript("before", [call("m1", at: at(5), input: 1)])
    write_transcript("inside", [call("m1", at: at(6, 30), input: 1)])

    flagged = usage.report(since: at(6))
    assert_equal at(6).iso8601, flagged["cutoff"]
    assert_equal "since", flagged["cutoff_source"]

    File.write(@rate_limits, JSON.generate("five_hour" => 69, "resets_at" => at(11).to_i.to_s))
    reset = usage.report
    assert_equal at(6).iso8601, reset["cutoff"]
    assert_equal "rate-limit reset", reset["cutoff_source"]
    assert_equal ["inside"], reset["sessions"].map { |s| s["id"] }

    File.write(@rate_limits, JSON.generate("five_hour" => 69, "resets_at" => at(9).to_i.to_s))
    stale = usage.report
    assert_equal at(5).iso8601, stale["cutoff"]
    assert_equal "last 5 hours", stale["cutoff_source"]

    FileUtils.rm_f(@rate_limits)
    assert_equal "last 5 hours", usage.report["cutoff_source"]
  end

  def test_unparsable_record_counted_and_named
    path = write_transcript("torn", [call("m1", at: at(7), cache_read: 1_000),
                                     '{"type":"assistant","message":{"id":"m2"',
                                     call("m3", at: at(7, 5), cache_read: 2_000)])
    report = usage.report(since: at(6))
    row = session(report, "torn")
    assert_equal 2, row["calls"]
    assert_equal 1, row["broken"]
    assert_equal [[path, 2]], report["broken"].map { |b| [b["file"], b["line"]] }
    assert_includes SessionUsage.render_text(report), "#{path}:2"
  end

  def test_missing_transcripts_dir_is_unavailable
    report = usage(root: File.join(@home, "missing")).report(since: at(6))
    assert_equal "unavailable", report["status"]
    refute report.key?("sessions")
    text = SessionUsage.render_text(report)
    assert_match(/unavailable/, text)
    refute_match(/calls/, text)
  end
end
