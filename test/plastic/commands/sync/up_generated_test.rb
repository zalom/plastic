# frozen_string_literal: true

require "json"
require_relative "../../../test_helper"

class SyncUpGeneratedTest < Plastic::TestCase
  include LifecycleHelper

  def index_path = store_path("store/index.json")

  def index_with_cluster
    data = JSON.parse(File.read(index_path))
    write("store/index.json", JSON.generate(data.merge("clusters" => [{ "name" => "imported", "intents" => ["1"] }])))
  end

  def test_sync_up_keeps_a_context_file_that_has_no_rows
    intent = open_intent
    path = "#{intent.dir}/context.json"
    write(path, "{}\n")
    result = cli("sync", "up")

    assert_equal [0, "{}\n"], [result.code, File.read(store_path(path))], result.err
  end

  def test_sync_up_prints_a_generated_index_with_other_content_and_leaves_it_level
    open_intent
    index_with_cluster
    result = cli("sync", "up")
    printed = File.read(index_path)

    assert_equal [0, "#{JSON.pretty_generate(JSON.parse(printed))}\n", true], [result.code, printed, printed.include?("imported")], result.err
  end

  def test_a_preview_of_sync_up_counts_the_generated_file_it_would_print_and_changes_nothing
    open_intent
    index_with_cluster
    before = File.read(index_path)
    result = cli("sync", "up", "--dry-run")

    assert_equal [0, true, before], [result.code, result.out.include?("paths that would change: 1"), File.read(index_path)], result.err
  end

  def test_sync_up_leaves_a_re_indented_index_alone
    open_intent
    compact = JSON.generate(JSON.parse(File.read(index_path)))
    write("store/index.json", compact)
    result = cli("sync", "up")

    assert_equal [0, compact], [result.code, File.read(index_path)], result.err
  end

  def test_sync_up_names_the_overwrite_that_clears_a_file_it_cannot_read
    specified
    other = open_intent("Beta")
    write("#{other.dir}/graph.json", "{\"hand\":true}\n")
    result = cli("sync", "up")

    assert_equal [1, true], [result.code, result.out.include?("sync down --overwrite #{other.dir}/graph.json")], result.err
  end

  # A preview copies committed files, so it runs in a home of its own: the dry run, the file it left, then the real run.
  def preview_then_apply(path, text)
    with_home do |home|
      yield home
      file = File.join(home, "stores", "global", path)
      File.write(file, text)
      [call_in(home, "sync", "up", "--dry-run"), File.read(file), call_in(home, "sync", "up")]
    end
  end

  def test_a_preview_of_sync_up_names_a_file_it_cannot_read_and_exits_as_the_real_run_does
    path = "store/1--beta/graph.json"
    dry, kept, real = preview_then_apply(path, "{\"hand\":true}\n") { |home| call_in(home, "intent", "new", "Beta") }

    assert_equal [1, true, "{\"hand\":true}\n", 1], [dry.code, dry.err.include?("sync down --overwrite #{path}"), kept, real.code], dry.out + dry.err
  end

  def test_a_preview_of_sync_up_names_a_changed_roadmap_it_would_print_again_and_exits_as_the_real_run_does
    dry, kept, real = preview_then_apply("roadmaps/r1.md", "# by hand\n") { |home| call_in(home, "roadmap", "new", "r1") }

    assert_equal [0, true, "# by hand\n", 0], [dry.code, dry.out.include?("preview: printed again from rows: roadmaps/r1.md"), kept, real.code], dry.out + dry.err
  end

  def conflicting_spec(home)
    call_in(home, "intent", "new", "Beta")
    spec = File.join(home, "stores", "global", "store/1--beta/spec.md")
    File.write(spec, "# Spec\n\n## Done criteria\n- [ ] [done] it is done\n")
    call_in(home, "sync", "up")
    home_graphs(home).databases[:knowledge].transaction { |batch| batch.put(:documents, { intent_id: "1", path: "spec.md", body: "row change", updated_at: STAMP }) }
    File.write(spec, "file change\n")
  end

  def test_a_preview_of_sync_up_refuses_a_conflict_as_the_real_run_does_also_with_merge
    codes = [[], ["--merge"]].flat_map do |options|
      with_home do |home|
        conflicting_spec(home)
        [call_in(home, "sync", "up", "--dry-run", *options).code, call_in(home, "sync", "up", *options).code]
      end
    end

    assert_equal [3, 3, 3, 3], codes
  end

  def test_a_preview_of_sync_up_with_an_overwrite_that_names_no_file_prints_the_plain_reason
    dry = with_home { |home| call_in(home, "sync", "up", "--dry-run", "--overwrite", "store/9--none/spec.md") }

    assert_equal [1, "plastic: store/9--none/spec.md names no file and no rows of this store\n"], [dry.code, dry.err], dry.out
  end
end
