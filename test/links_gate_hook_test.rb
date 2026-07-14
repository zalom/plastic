# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "json"

# ACTION_1 (intent 192): drive the real scripts/hook-links-gate as a subprocess
# with a JSON PreToolUse payload on stdin, proving the wiring (JSON ->
# LinksGate -> exit code/stderr) works end to end. The bulk of decision-logic
# coverage lives in test/links_gate_test.rb (LinksGate directly, hermetic and
# fast); this file only proves the hook script itself is wired correctly.
class LinksGateHookTest < Minitest::Test
  SCRIPT = File.expand_path("../scripts/hook-links-gate", __dir__)

  def setup
    @home = Dir.mktmpdir("links-gate-hook")
    @store = File.join(@home, "store")
    FileUtils.mkdir_p(@store)
    File.write(File.join(@home, "INDEX.md"), "# Index\n\n## Relocated\n(none)\n\n## Completed\n")
  end

  def teardown
    FileUtils.remove_entry(@home) if @home && Dir.exist?(@home)
  end

  def write_intent(basename, id:, intent:, sources:, chain:, links:)
    dir = File.join(@store, basename)
    FileUtils.mkdir_p(dir)
    content = +"---\n"
    content << "id: \"#{id}\"\nintent: \"#{intent}\"\n"
    content << "sources: #{flow(sources)}\nchain: #{flow(chain)}\n"
    content << "created: 2026-07-01\nauthor: test\ntags: [t]\n---\n\n## Intent\nBody #{id}.\n\n"
    content << links
    path = File.join(dir, "#{basename}.md")
    File.write(path, content)
    path
  end

  def flow(ids)
    ids.empty? ? "[]" : "[#{ids.map { |i| "\"#{i}\"" }.join(", ")}]"
  end

  def run_gate(payload)
    env = { "PLASTIC_HOME" => @home }
    out = IO.popen(env, [RbConfig.ruby, SCRIPT], "r+", err: [:child, :out]) do |io|
      io.write(JSON.generate(payload))
      io.close_write
      io.read
    end
    [out, $?.exitstatus]
  end

  def test_write_of_a_hand_typed_unbacked_bullet_is_denied
    path = write_intent("20--subject", id: "20", intent: "Subject", sources: [], chain: [],
                         links: "## Links\n<!-- No sources or chain; this intent has no graph edges to project. -->\n")
    content = File.read(path).sub(
      "<!-- No sources or chain; this intent has no graph edges to project. -->\n",
      "- [[99--nowhere|Nowhere]]\n"
    )
    out, status = run_gate({ "tool_input" => { "file_path" => path, "content" => content } })
    assert_equal 2, status, "hand-typed unbacked bullet must be denied: #{out}"
    assert_includes out, "PLASTIC LINKS GATE"
  end

  def test_edit_that_leaves_links_untouched_is_allowed
    path = write_intent("20--subject", id: "20", intent: "Subject", sources: [], chain: [],
                         links: "## Links\n<!-- No sources or chain; this intent has no graph edges to project. -->\n")
    original = File.read(path)
    payload = { "tool_input" => { "file_path" => path, "old_string" => "Body 20.",
                                   "new_string" => "Body 20, edited." } }
    _out, status = run_gate(payload)
    assert_equal 0, status
    assert_equal original, File.read(path), "the hook must not itself write anything"
  end

  def test_non_intent_file_is_allowed
    path = File.join(@home, "notes.md")
    File.write(path, "hello")
    _out, status = run_gate({ "tool_input" => { "file_path" => path, "content" => "hello, edited" } })
    assert_equal 0, status
  end

  def test_pathless_mutation_with_no_visible_proposal_is_allowed
    path = write_intent("20--subject", id: "20", intent: "Subject", sources: [], chain: [],
                         links: "## Links\n<!-- No sources or chain; this intent has no graph edges to project. -->\n")
    _out, status = run_gate({ "tool_input" => { "file_path" => path } })
    assert_equal 0, status
  end
end
