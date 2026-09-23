require_relative "test_helper"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/untouched_scaffold"

# UntouchedScaffold.reason names an intent that is still exactly its new-intent
# scaffold (acceptance N3); every sign of work returns nil.
class UntouchedScaffoldTest < Minitest::Test
  SENTINEL = Savepoint::PLACEHOLDER_SENTINEL

  def setup
    @dir = Dir.mktmpdir("untouched-scaffold")
    FileUtils.mkdir_p(File.join(@dir, "actions"))
    UntouchedScaffold::LIFECYCLE.each { |rel| write(rel, "#{SENTINEL}\n# #{rel}\n") }
    write("savepoint.md", "2026-09-23T01:00:00Z  What  1--demo.md\n\n")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def write(rel, text)
    File.write(File.join(@dir, rel), text)
  end

  def reason(**opts)
    UntouchedScaffold.reason(@dir, **opts)
  end

  def test_an_untouched_scaffold_is_named
    assert_equal "spec.md, plan.md, checklist.md and outcome.md are still placeholders, " \
                 "no action, node or graph was written, the savepoint records no work, " \
                 "and the code worktree has no changes", reason
  end

  def test_a_missing_lifecycle_file_is_legacy_not_a_scaffold
    File.delete(File.join(@dir, "plan.md"))

    assert_nil reason
  end

  def test_a_real_lifecycle_file_is_work
    write("spec.md", "# Spec\n\nreal\n")

    assert_nil reason
  end

  def test_a_ticked_checklist_item_is_work
    write("checklist.md", "#{SENTINEL}\n# Checklist\n\n- [x] S1 done\n")

    assert_nil reason
  end

  def test_an_unticked_template_item_is_not_work
    write("checklist.md", "#{SENTINEL}\n# Checklist\n\n- [ ] S1 to do\n")

    refute_nil reason
  end

  def test_text_written_under_a_sentinel_is_work
    write("spec.md", "#{SENTINEL}\n# Spec\n\nthe owner wrote this\n")

    assert_nil reason(templates: {"spec.md" => "# Spec\n"})
  end

  def test_template_text_under_a_sentinel_is_not_work
    write("spec.md", "#{SENTINEL}\n# Spec\n\n## Goals\n")

    refute_nil reason(templates: {"spec.md" => "# Spec\n\n## Goals\n"})
  end

  def test_a_real_action_is_work
    write("actions/ACTION_1.md", "# ACTION_1\n\n### S1 - thing\n")

    assert_nil reason
  end

  def test_a_graph_is_work
    write("graph.md", "#{SENTINEL}\n")

    assert_nil reason
  end

  def test_a_savepoint_line_past_what_is_work
    File.open(File.join(@dir, "savepoint.md"), "a") { |f| f.puts "2026-09-23T02:00:00Z  Report  progress" }

    assert_nil reason
  end

  def test_a_missing_savepoint_is_legacy
    File.delete(File.join(@dir, "savepoint.md"))

    assert_nil reason
  end

  def test_worktree_changes_are_work
    seen = []

    assert_nil reason(worktree_changed: ->(dir) { seen << dir })
    assert_equal [@dir], seen
  end

  def test_an_unchanged_worktree_leaves_the_scaffold_untouched
    refute_nil reason(worktree_changed: ->(_dir) { false })
  end
end
