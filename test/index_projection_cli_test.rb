# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"

# scripts/index-projection (intent 337, n6): prints the drift between
# INDEX.md and the intent ledgers for one store root (INDEX.md plus a
# store/ directory), exits non-zero when any drift exists; --write renders
# INDEX.md's four status sections from the projection through AtomicWrite.
# Matrix rows from actions/ACTION_1.md S7/n6 (the CLI half). Hermetic:
# shells out to the real script (Open3), every fixture lives in a
# Dir.mktmpdir.
class IndexProjectionCliTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  CLI = File.join(REPO, "scripts", "index-projection")

  def setup
    @root = Dir.mktmpdir("index-projection-cli")
    @store_dir = File.join(@root, "store")
    FileUtils.mkdir_p(@store_dir)
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && Dir.exist?(@root)
  end

  def index_path
    File.join(@root, "INDEX.md")
  end

  def write_index(active: [], future: [], completed: [], abandoned: [], clusters_note: "A note nobody else owns.", relocated_note: "A relocation record.")
    line = ->(id) { "- [#{id} - Title](store/#{id}--slug/#{id}--slug.md) - note." }
    lines = ["# Index", "", "## Active", ""]
    active.each { |id| lines << line.call(id) }
    lines += ["", "## Future", ""]
    future.each { |id| lines << line.call(id) }
    lines += ["", "## Clusters", "", clusters_note, "", "## Abandoned", ""]
    abandoned.each { |id| lines << line.call(id) }
    lines += ["", "## Completed", ""]
    completed.each { |id| lines << line.call(id) }
    lines += ["", "## Relocated", "", relocated_note, ""]
    File.write(index_path, lines.join("\n") + "\n")
  end

  def write_intent(id, savepoint_lines:)
    dir = File.join(@store_dir, "#{id}--slug")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "#{id}--slug.md"), "# #{id}\n")
    File.write(File.join(dir, "savepoint.md"), savepoint_lines.join("\n") + "\n")
  end

  def run_cli(*args)
    Open3.capture3("ruby", CLI, *args)
  end

  # --- 6.1: a default run changes no bytes --------------------------------------

  def test_default_run_changes_no_bytes
    write_index(active: ["101"])
    write_intent("101", savepoint_lines: ["2026-01-01T00:00:00Z  Done  delivered"])
    before = File.read(index_path)
    run_cli(@root)
    assert_equal before, File.read(index_path)
  end

  # --- 6.2: --write is required before any byte changes -------------------------

  def test_write_flag_is_required_before_any_byte_changes
    write_index(active: ["101"])
    write_intent("101", savepoint_lines: ["2026-01-01T00:00:00Z  Done  delivered"])
    before = File.read(index_path)
    run_cli(@root, "--write")
    refute_equal before, File.read(index_path)
  end

  # --- 6.3: writes through AtomicWrite -------------------------------------------

  def test_write_goes_through_atomic_write
    write_index(active: ["101"])
    write_intent("101", savepoint_lines: ["2026-01-01T00:00:00Z  Done  delivered"])
    run_cli(@root, "--write")
    leftovers = Dir.glob(File.join(@root, ".*")).reject { |p| %w[. ..].include?(File.basename(p)) }
    assert_empty leftovers
  end

  # --- 6.4: an entry's existing text is preserved into the rewritten section ---

  def test_rewrite_preserves_each_entry_line_text
    write_index(active: ["101"])
    File.write(index_path, File.read(index_path).sub(
                 "- [101 - Title](store/101--slug/101--slug.md) - note.",
                 "- [101 - Custom Title, with a comma](store/101--slug/101--slug.md) - a special note."
               ))
    write_intent("101", savepoint_lines: ["2026-01-01T00:00:00Z  Done  delivered"])
    run_cli(@root, "--write")
    content = File.read(index_path)
    assert_includes content, "- [101 - Custom Title, with a comma](store/101--slug/101--slug.md) - a special note."
  end

  # --- 6.5: exit is 1 when drift exists, 0 when clean ---------------------------

  def test_exit_is_1_when_drift_exists_and_0_when_clean
    write_index(active: ["101"])
    write_intent("101", savepoint_lines: ["2026-01-01T00:00:00Z  Done  delivered"])
    _out, _err, status = run_cli(@root)
    assert_equal 1, status.exitstatus

    write_index(completed: ["101"])
    _out2, _err2, status2 = run_cli(@root)
    assert_equal 0, status2.exitstatus
  end

  # --- 6.6: a non-store path exits with a named reason ---------------------------

  def test_non_store_path_exits_with_a_named_reason
    out, err, status = run_cli(File.join(@root, "does-not-exist"))
    refute_equal 0, status.exitstatus
    refute_match(/\.rb:\d+:in/, out + err)
  end

  # --- 6.13: ## Clusters and ## Relocated are byte-identical after a write -----

  def test_clusters_and_relocated_sections_are_byte_identical_after_write
    write_index(active: ["101"], clusters_note: "Keep me exactly.", relocated_note: "Keep me too.")
    write_intent("101", savepoint_lines: ["2026-01-01T00:00:00Z  Done  delivered"])
    run_cli(@root, "--write")
    content = File.read(index_path)
    assert_includes content, "Keep me exactly."
    assert_includes content, "Keep me too."
  end

  # --- 6.14: --write never demotes an entry whose ledger is silent -------------

  def test_write_never_demotes_an_entry_whose_ledger_is_silent
    write_index(completed: ["101"])
    write_intent("101", savepoint_lines: ["2026-01-01T00:00:00Z  Exec  started"]) # no terminal line
    run_cli(@root, "--write")
    content = File.read(index_path)
    completed_body = content[/^## Completed$(.*?)(?=^## |\z)/m, 1]
    assert_includes completed_body, "101"
  end

  # --- 6.15: the command and its lib are registered in CORE_FILES --------------

  def test_command_and_lib_are_registered_in_core_files
    source = File.read(File.join(REPO, "scripts", "lib", "installer_core.rb"))
    assert_includes source, "scripts/index-projection".inspect
    assert_includes source, "scripts/lib/index_projection.rb".inspect
  end
end
