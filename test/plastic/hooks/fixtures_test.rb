# frozen_string_literal: true

require_relative "../../test_helper"
require "json"
require_relative "../../../lib/plastic/harnesses/detection"

# The scrubbed hook events of Claude Code and Codex. A fixture named
# `.documented` was written from the documented event shape; the others were
# captured from a real run and scrubbed.
class HookFixturesTest < Plastic::TestCase
  FOLDER = File.expand_path("../../fixtures/hooks", __dir__)
  PRIVATE = [%r{/Users/}, %r{/home/(?!user)\w}, /sk-[A-Za-z0-9]{8,}/, /\bghp_\w+/, /api[_-]?key/i, /\bpassword\b/i, /\bBearer\s/].freeze
  EXPECTED = {
    "claude-code" => %w[session_start_compact prompt_submit stop],
    "codex" => %w[session_start_compact prompt_submit stop]
  }.freeze

  def fixtures = Dir.children(FOLDER).sort

  def event(name) = JSON.parse(File.read(File.join(FOLDER, name)), symbolize_names: true)

  def named(harness, kind) = fixtures.find { |name| name.start_with?("#{harness.tr("-", "_")}_#{kind}") }

  def harness_of(event) = Plastic::Harnesses::Detection.new(event:, env: {}, processes: []).harness

  def test_the_fixtures_are_read_from_the_disk
    refute_empty fixtures
  end

  def test_every_harness_has_a_fixture_for_each_event
    EXPECTED.each { |harness, kinds| kinds.each { |kind| refute_nil named(harness, kind), "#{harness} #{kind}" } }
  end

  def test_detection_names_the_harness_that_wrote_each_fixture
    EXPECTED.each do |harness, kinds|
      kinds.each { |kind| assert_equal harness, harness_of(event(named(harness, kind))), named(harness, kind) }
    end
  end

  def test_each_fixture_carries_the_event_name_and_the_fields_the_hooks_read
    fixtures.each do |name|
      found = event(name)

      assert_equal %i[cwd hook_event_name session_id transcript_path], (found.keys & %i[cwd hook_event_name session_id transcript_path]).sort, name
    end
  end

  def test_a_compact_start_names_its_source_and_a_stop_names_the_last_message
    assert_equal "compact", event(named("claude-code", "session_start_compact"))[:source]
    assert_equal "ready", event(named("claude-code", "stop"))[:last_assistant_message]
  end

  def hook(name, kind)
    plastic("hook", name, input: File.read(File.join(FOLDER, named("claude-code", kind))), table: Plastic::CLI::TABLE)
  end

  def test_the_start_hook_reads_the_compact_fixture_and_records_the_session_for_its_harness
    result = hook("start", "session_start_compact")

    assert_equal 0, result.code
    assert_equal "claude-code", store_graphs.retrieval.session("00000000-0000-4000-8000-000000000001").harness
  end

  def test_the_stop_hook_reads_the_stop_fixture_and_prints_nothing
    hook("start", "session_start_compact")
    result = hook("stop", "stop")

    assert_equal [0, ""], [result.code, result.err]
  end

  def test_no_fixture_holds_a_home_path_or_a_key
    fixtures.each { |name| PRIVATE.each { |pattern| refute_match pattern, File.read(File.join(FOLDER, name)), name } }
  end

  def test_the_detector_catches_a_home_path_and_a_key_and_leaves_a_scrubbed_line_alone
    assert(PRIVATE.any? { |pattern| "/Users/someone/x".match?(pattern) })
    assert(PRIVATE.any? { |pattern| "sk-abcdef123456".match?(pattern) })
    refute(PRIVATE.any? { |pattern| "/work/project".match?(pattern) })
  end
end
