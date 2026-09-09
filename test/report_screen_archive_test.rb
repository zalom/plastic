# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "open3"
require_relative "../scripts/lib/report_screen"

# report-screen archive <store_root> (intent 339, G6, n6): a read-only view of
# a store's terminal intents, the reading half of intent 132 (spec D9). Never
# a move: not one path or mtime under store/ changes.
class ReportScreenArchiveTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)
  CLI = File.join(REPO, "scripts", "report-screen")

  def setup
    @root = Dir.mktmpdir("report-screen-archive")
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def make_intent(dirname, outcome: nil)
    dir = File.join(@root, "store", dirname)
    FileUtils.mkdir_p(dir)
    id = dirname.split("--", 2).first
    File.write(File.join(dir, "#{dirname}.md"), "---\nid: \"#{id}\"\nintent: \"Demo\"\n---\n\n## Intent\nDemo\n")
    File.write(File.join(dir, "outcome.md"), outcome) if outcome
    dir
  end

  def write_index(active: [], completed: [], abandoned: [])
    lines = ["# Index", "", "## Active"]
    active.each { |d| lines << "- [#{d} - x](store/#{d}/#{d}.md)" }
    lines << "" << "## Future" << "" << "## Completed"
    completed.each { |d| lines << "- [#{d} - x](store/#{d}/#{d}.md)" }
    lines << "" << "## Abandoned"
    abandoned.each { |d| lines << "- [#{d} - x](store/#{d}/#{d}.md)" }
    File.write(File.join(@root, "INDEX.md"), "#{lines.join("\n")}\n")
  end

  # --- 6.1 -------------------------------------------------------------------

  def test_archive_lists_terminal_sections_only
    make_intent("1--active", outcome: "---\ndisposition: delivered\n---\n")
    make_intent("2--done", outcome: "---\ndisposition: delivered\n---\n")
    write_index(active: ["1--active"], completed: ["2--done"])
    out = ReportScreen.render_archive(@root)
    refute_includes out, "1--active"
    assert_includes out, "2--done"
  end

  # --- 6.2 -------------------------------------------------------------------

  def test_disposition_read_from_outcome_frontmatter
    make_intent("2--done", outcome: "---\ndisposition: delivered\n---\n")
    make_intent("3--abandoned", outcome: "---\ndisposition: abandoned\n---\n")
    write_index(completed: ["2--done"], abandoned: ["3--abandoned"])
    out = ReportScreen.render_archive(@root)
    row_done = out.lines.find { |l| l.include?("2--done") }
    row_abandoned = out.lines.find { |l| l.include?("3--abandoned") }
    assert_includes row_done, "delivered"
    assert_includes row_abandoned, "abandoned"
  end

  # --- 6.3 -------------------------------------------------------------------

  def test_missing_outcome_renders_not_recorded
    make_intent("2--done")
    write_index(completed: ["2--done"])
    out = ReportScreen.render_archive(@root)
    row = out.lines.find { |l| l.include?("2--done") }
    assert_includes row, ReportScreen::NOT_RECORDED
  end

  # --- 6.4 -------------------------------------------------------------------

  def test_archive_changes_no_path_or_mtime
    make_intent("2--done", outcome: "---\ndisposition: delivered\n---\n")
    write_index(completed: ["2--done"])

    before = Dir.glob(File.join(@root, "store", "**", "*"), File::FNM_DOTMATCH)
                .reject { |p| File.basename(p) == "." || File.basename(p) == ".." }
                .sort.map { |p| [p, File.exist?(p) ? File.mtime(p) : nil] }

    ReportScreen.render_archive(@root)

    after = Dir.glob(File.join(@root, "store", "**", "*"), File::FNM_DOTMATCH)
               .reject { |p| File.basename(p) == "." || File.basename(p) == ".." }
               .sort.map { |p| [p, File.exist?(p) ? File.mtime(p) : nil] }

    assert_equal before, after
  end

  # --- 6.5 -------------------------------------------------------------------

  def test_non_store_path_exits_2
    _out, err, status = Open3.capture3("ruby", CLI, "archive", @root)
    assert_equal 2, status.exitstatus
    refute_empty err
  end

  # --- 6.6 -------------------------------------------------------------------

  def test_usage_line_names_archive
    source = File.read(CLI)
    assert_match(/archive/, source)
    assert_includes source, "report-screen archive <store_root>"
  end
end
