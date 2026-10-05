# frozen_string_literal: true

require_relative "../../test_helper"

class RoadmapShowTest < Plastic::TestCase
  def cli(*args) = plastic(*args, table: Plastic::CLI::TABLE)

  def test_show_prints_the_batch_its_criteria_and_its_items
    cli("roadmap", "batch", "r1", "1", "--title", "Wave one", "--goal", "Ship it", "--done", "a done", "--done", "b done")
    cli("roadmap", "add", "r1", "1", "a", "--title", "A")

    result = cli("roadmap", "show", "r1")

    assert_call result, code: 0, out: ["batch 1: Wave one - Ship it\n  done: a done\n  done: b done\n",
      "item a: A - ", "waits for nothing", "next: plastic roadmap next r1"]
  end

  def test_show_on_a_missing_roadmap_names_it
    result = cli("roadmap", "show", "r9")

    assert_call result, code: 1, err: "plastic: code_show_roadmap, gate: no roadmap r9\n"
  end

  def test_a_preview_leaves_the_roadmap_file_as_it_was
    twin = twin_run("roadmap", "show", "r1") do |home|
      seed_roadmap(home, "a")
      call_in(home, "roadmap", "show", "r1")
      File.write(File.join(home, "stores", "global", "roadmaps", "r1.md"), "hand edit\n")
    end
    path = File.join(twin.first, "stores", "global", "roadmaps", "r1.md")

    assert_equal "hand edit\n", File.read(path)
    assert_equal [], twin.changed_paths
    assert_includes twin.preview_paths, "change #{path}"
  end

  def test_preview_matches_apply_on_an_identical_home
    twin = twin_run("roadmap", "show", "r1") { |home| seed_roadmap(home, "a", "b") }

    assert_preview_matches_apply(twin)
    assert_includes twin.previewed_lines, "batch 1: T - G"
  end

  def test_a_preview_with_a_linked_roadmaps_folder_refuses_and_the_outside_folder_is_untouched
    with_home do |home|
      seed_roadmap(home, "a")
      call_in(home, "roadmap", "show", "r1")
      outside = File.join(File.dirname(home), "outside")
      FileUtils.mv(File.join(home, "stores", "global", "roadmaps"), outside)
      File.symlink(outside, File.join(home, "stores", "global", "roadmaps"))
      before = [snapshot(home), snapshot(outside)]

      result = call_in(home, "roadmap", "show", "r1", "--dry-run")

      assert_equal 3, result.code
      assert_includes result.err, File.join(home, "stores", "global", "roadmaps")
      assert_equal before, [snapshot(home), snapshot(outside)]
    end
  end
end
