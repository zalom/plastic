# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"

require_relative "../scripts/lib/node_input_compatibility"
require_relative "../scripts/lib/node_ledger"

# Intent 338a (G6), n1: the compatibility reader. Matrix rows 1.1-1.5 in
# nodes/n1.md. `NodeInputCompatibility::LEGACY_FIELD` is the one place the
# retired field name is allowed to appear outside this test.
class NodeInputCompatibilityTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)

  # --- 1.1: a parsed legacy field maps to input -------------------------------

  def test_legacy_field_reads_as_input
    mapped = NodeInputCompatibility.fields({ "holder" => "h", NodeInputCompatibility::LEGACY_FIELD => "abc123" })
    assert_equal "abc123", mapped["input"]
  end

  # --- 1.2: input wins when both names are present ----------------------------

  def test_input_wins_over_the_legacy_field
    mapped = NodeInputCompatibility.fields(
      { "input" => "new-sha", NodeInputCompatibility::LEGACY_FIELD => "old-sha" }
    )
    assert_equal "new-sha", mapped["input"]
  end

  # --- 1.3: the raw ledger line is never rewritten ----------------------------

  def test_raw_line_is_not_rewritten
    raw = "2026-09-13T00:00:00Z  n1  running holder=h expires=2026-09-13T01:00:00Z " \
          "#{NodeInputCompatibility::LEGACY_FIELD}=abc123 model=sonnet\n"
    entries = NodeLedger.entries_from_content(raw)
    assert_equal raw.chomp, entries.first[:raw]
  end

  # --- 1.4: no other project file is loaded -----------------------------------

  def test_loads_no_other_project_file
    lib = File.join(REPO, "scripts", "lib", "node_input_compatibility.rb")
    out, err, status = Open3.capture3({ "RUBYOPT" => nil }, RbConfig.ruby, "-e",
                                       "require #{lib.inspect}; puts $LOADED_FEATURES")
    assert status.success?, "node_input_compatibility.rb does not load: #{err}"
    loaded = out.lines.map(&:strip)
    project = loaded.select { |f| f.start_with?("#{REPO}/") }.map { |f| f.sub("#{REPO}/", "") }.sort
    assert_equal %w[scripts/lib/node_input_compatibility.rb], project
  end

  # --- 1.5: a legacy running line still counts as an attempt ------------------

  def test_legacy_running_line_counts_as_an_attempt
    raw = "2026-09-13T00:00:00Z  n1  running holder=h expires=2026-09-13T01:00:00Z " \
          "#{NodeInputCompatibility::LEGACY_FIELD}=abc123 model=sonnet\n"
    entries = NodeLedger.entries_from_content(raw)
    running = entries.count { |e| !e[:torn] && e[:subject] == "n1" && e[:state] == "running" }
    assert_equal 1, running
  end
end
