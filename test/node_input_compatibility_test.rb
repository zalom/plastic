# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require "fileutils"
require "tmpdir"

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

  # --- 338a n3, 3.9-3.11: the legacy input path, resolved by the reader's own constants -

  def test_legacy_input_path_resolves_when_the_new_file_is_absent
    Dir.mktmpdir("node-input-compatibility") do |dir|
      legacy_dir = File.join(dir, NodeInputCompatibility::LEGACY_DIRECTORY)
      FileUtils.mkdir_p(legacy_dir)
      legacy_file = File.join(legacy_dir, "n1--a1#{NodeInputCompatibility::LEGACY_SUFFIX}")
      File.write(legacy_file, "hello")

      resolved = NodeInputCompatibility.input_path(intent_dir: dir, node: "n1", attempt: 1)
      assert_equal legacy_file, resolved
    end
  end

  def test_new_input_path_wins_when_both_exist
    Dir.mktmpdir("node-input-compatibility") do |dir|
      new_dir = File.join(dir, "attempts")
      FileUtils.mkdir_p(new_dir)
      new_file = File.join(new_dir, "n1--a1.input")
      File.write(new_file, "new")

      legacy_dir = File.join(dir, NodeInputCompatibility::LEGACY_DIRECTORY)
      FileUtils.mkdir_p(legacy_dir)
      File.write(File.join(legacy_dir, "n1--a1#{NodeInputCompatibility::LEGACY_SUFFIX}"), "old")

      resolved = NodeInputCompatibility.input_path(intent_dir: dir, node: "n1", attempt: 1)
      assert_equal new_file, resolved
    end
  end

  def test_missing_input_names_the_new_path
    Dir.mktmpdir("node-input-compatibility") do |dir|
      expected = File.join(dir, "attempts", "n1--a1.input")
      resolved = NodeInputCompatibility.input_path(intent_dir: dir, node: "n1", attempt: 1)
      assert_equal expected, resolved
    end
  end
end
