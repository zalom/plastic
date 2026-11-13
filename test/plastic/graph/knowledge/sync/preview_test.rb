# frozen_string_literal: true

require_relative "../../../../test_helper"

module DryRunAssertions
  DATABASE_FILE = /\.db(-wal|-shm|-journal)?\z/

  def preview(direction: :up, **options) = Plastic::Graph::Knowledge::Sync::Preview.new(@plastic_home, "global", options, direction:).call

  def files_of_store = snapshot(store_root).reject { |rel, _| rel.match?(DATABASE_FILE) }

  def listed_paths(lines) = lines.filter_map { |line| line[/\Apreview: would (?:add|change|remove) (.+)\z/, 1] }

  def paths_the_real_run_touches(direction)
    before = files_of_store
    work = store_graphs.work
    work.sync_apply(work.sync_plan(direction, {}))
    after = files_of_store
    (before.keys | after.keys).reject { |rel| before[rel] == after[rel] }.sort
  end

  def assert_dry_run_names_what_the_real_run_touches(direction)
    lines = preview(direction:)
    listed = listed_paths(lines).sort

    refute_empty listed
    assert_equal paths_the_real_run_touches(direction), listed
    assert_includes lines, "preview: paths that would change: #{listed.size}"
  end

  def stat_of(path)
    stat = File.stat(path)
    [File.binread(path), stat.ino, stat.mtime, stat.nlink, stat.size]
  end

  def states
    Dir.glob("**/*", File::FNM_DOTMATCH, base: store_root).select { |rel| File.file?(store_path(rel)) }.sort.to_h { |rel| [rel, stat_of(store_path(rel))] }
  end
end

class KnowledgeSyncPreviewTest < Plastic::TestCase
  include DryRunAssertions

  fixtures :alpha_synced

  SPEC = "store/1--alpha/spec.md"

  def conflicting_spec
    store_graphs.databases[:knowledge].transaction do |batch|
      batch.put(:documents, { intent_id: "1", path: "spec.md", body: "row change", updated_at: STAMP })
    end
    write(SPEC, "file change")
  end

  def test_absolute_overwrite_path_is_resolved_against_original_store
    conflicting_spec
    before = snapshot(store_root)

    assert_includes preview(overwrite: store_path(SPEC)), "preview: read #{SPEC}"
    assert_equal before, snapshot(store_root)
  end

  def test_an_overwrite_path_that_names_no_file_is_refused_naming_the_path
    error = assert_raises(Plastic::Invalid) { preview(overwrite: "store/9--nothing/spec.md") }

    assert_includes error.message, "store/9--nothing/spec.md names no file"
  end

  def test_a_dry_run_of_sync_up_names_the_files_the_real_run_touches_on_a_synced_store
    write("store/2--beta/intent.md", "---\nid: 2\nintent: Beta\ncreated: #{STAMP}\nstatus: open\n---\n")
    write(SPEC, "file change")

    assert_dry_run_names_what_the_real_run_touches(:up)
  end

  def test_a_dry_run_of_sync_down_names_the_files_the_real_run_touches_on_a_synced_store
    File.delete(store_path(SPEC))

    assert_dry_run_names_what_the_real_run_touches(:down)
  end

  def test_the_files_of_the_store_keep_their_bytes_and_inode_data_after_a_dry_run
    write(SPEC, "file change")
    before = states
    preview

    assert_equal before, states
  end

  def copies_made_by
    copied = []
    original = FileUtils.method(:cp_r)
    FileUtils.define_singleton_method(:cp_r) { |*args, **options| copied << args.tap { original.call(*args, **options) } }
    yield
    copied
  ensure
    FileUtils.define_singleton_method(:cp_r, original)
  end

  def test_a_dry_run_copies_no_file_of_the_store_and_leaves_no_folder_behind
    write(SPEC, "file change")
    entries = Dir.children(@plastic_home).sort

    assert_empty copies_made_by { preview }
    assert_equal entries, Dir.children(@plastic_home).sort
  end

  def test_a_symbolic_link_is_rejected_before_copying
    target = File.join(@plastic_home, "outside")
    File.write(target, "keep")
    File.symlink(target, store_path("store/1--alpha/link"))
    error = assert_raises(Plastic::Invalid) { preview }

    assert_includes error.message, "symbolic link"
    assert_equal "keep", File.read(target)
  end
end

class KnowledgeSyncPreviewLegacyTest < Plastic::TestCase
  include DryRunAssertions

  fixtures :legacy

  def test_a_dry_run_of_sync_up_names_the_files_the_real_run_touches_on_a_legacy_store
    assert_dry_run_names_what_the_real_run_touches(:up)
  end

  def test_the_files_of_a_legacy_store_keep_their_bytes_and_inode_data_after_a_dry_run
    before = states
    preview

    assert_equal before, states
  end
end
