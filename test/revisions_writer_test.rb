# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../scripts/lib/revisions_writer"

class RevisionsWriterTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("plastic-revisions-writer")
  end

  def teardown
    FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
  end

  def test_render_entry_matches_the_documented_shape
    text = RevisionsWriter.render_entry(3, why: "dangling ref", rule: "dangling-ref",
                                         prior_location: "intent.md ## Links",
                                         change: "removed \"x\"", timestamp: Time.utc(2026, 7, 16, 12, 0))
    assert_match(/\A## Revision v3 - 2026-07-16-12:00\n/, text)
    assert_includes text, "[rule: dangling-ref]"
    assert_includes text, "Prior location: intent.md ## Links"
  end

  def test_next_revision_number_is_one_when_file_absent
    assert_equal 1, RevisionsWriter.next_revision_number(nil)
  end

  def test_next_revision_number_increments_past_the_highest_existing
    existing = "# revisions.md\n\n## Revision v1 - x\n...\n\n## Revision v2 - x\n...\n"
    assert_equal 3, RevisionsWriter.next_revision_number(existing)
  end

  def test_append_creates_the_file_with_v1_when_absent
    n = RevisionsWriter.append!(@dir, why: "w", rule: "r", prior_location: "p", change: "c")
    assert_equal 1, n
    assert_includes File.read(File.join(@dir, "revisions.md")), "## Revision v1"
  end

  # FALSIFIABLE (208): a second append must APPEND v2, never overwrite v1's text.
  def test_append_is_append_only_never_overwrites
    RevisionsWriter.append!(@dir, why: "first", rule: "r1", prior_location: "p1", change: "c1")
    RevisionsWriter.append!(@dir, why: "second", rule: "r2", prior_location: "p2", change: "c2")
    text = File.read(File.join(@dir, "revisions.md"))
    assert_includes text, "## Revision v1"
    assert_includes text, "## Revision v2"
    assert_includes text, "first"
    assert_includes text, "second"
    assert_equal 2, text.scan(/^## Revision v\d+/).length
  end

  def test_write_failed_raised_when_directory_does_not_exist
    assert_raises(RevisionsWriter::WriteFailed) do
      RevisionsWriter.append!(File.join(@dir, "no-such-subdir"), why: "w", rule: "r",
                               prior_location: "p", change: "c")
    end
  end
end
