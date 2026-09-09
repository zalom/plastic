# ACTION_3 - new shared lib: scripts/lib/revisions_writer.rb

Covers the infrastructure half of spec.md AC: "`project-links`, `rebuild-graph`, and
`restore-intent-v1` each write (or already write) an append-only `revisions.md` entry on their
target intent in the same write as their change, or refuse to proceed without one." This
action builds the SHARED module; ACTION_4 and ACTION_5 wire it into project-links and
rebuild-graph. `restore-intent-v1` already has its own working, tested writer
(`scripts/lib/restore_intent_v1.rb:105-125`, `scripts/restore-intent-v1:264-277`) and is left
as-is (ACTION_6 only adds test coverage); this action does not touch it, per the "no
unnecessary churn on a passing tool" principle.

Discovery citation for the pattern being generalized: `scripts/lib/restore_intent_v1.rb`'s
`render_revision_entry` (pure text render) and `scripts/restore-intent-v1`'s `append_revision`
(the file IO: read-existing-or-seed, scan `## Revision v(\d+)`, take `max + 1`, write).

## 3a. New file: `scripts/lib/revisions_writer.rb`

```ruby
# encoding: UTF-8
# frozen_string_literal: true

# RevisionsWriter - the shared append-only revisions.md writer (intent 107's convention,
# generalized from restore_intent_v1.rb's proven pattern, intent 197). Every tool that
# performs structural maintenance on an intent (project-links, rebuild-graph,
# restore-intent-v1) must record it here: PLASTIC.md's `revisions.md` contract is that a
# structural change and its receipt are never separated. This module owns rendering ONE
# entry's text and appending it correctly; it does no git operations (that is
# lib/maintenance_git.rb's job) and never overwrites a prior entry.
#
# Pure where it can be (render_entry has no IO); the IO half (append!) is a thin,
# dependency-free file read/write, matching every other tool in scripts/lib.
module RevisionsWriter
  module_function

  # PURE. Renders one `## Revision vN - TIMESTAMP` entry in the documented shape
  # (PLASTIC-reference.md > Structural maintenance and revisions.md; templates/revisions.md).
  # `n` is the next revision number (caller resolves it via next_revision_number, or a caller
  # that already knows it, e.g. a batch writer amortizing one file read across many entries).
  # `why` is the one-sentence reason ending in "[rule: <tag>]" (tag is appended here if the
  # caller passes a bare sentence plus `rule:`, so every caller cannot forget the tag).
  # `prior_location` and `change` are free text (the "Change:" line for a metadata edit, or a
  # multi-line indented "Content held:" block for a relocated section/file - callers building
  # a Content-held entry should pass an already-indented `change` block).
  def render_entry(n, why:, rule:, prior_location:, change:, timestamp: Time.now.utc)
    ts = timestamp.strftime("%Y-%m-%d-%H:%M")
    lines = []
    lines << "## Revision v#{n} - #{ts}"
    lines << "- Why: #{why.to_s.strip} [rule: #{rule}]"
    lines << "- Prior location: #{prior_location}"
    lines << "- Change: #{change}"
    "#{lines.join("\n")}\n"
  end

  # PURE. Every existing "## Revision vN" number found in `existing_text` (empty array when
  # none, i.e. the file does not exist yet or carries no entries). Mirrors
  # scripts/restore-intent-v1's own `nums = existing.scan(/^## Revision v(\d+)/)` exactly, so
  # the two writers can never disagree about numbering.
  def revision_numbers(existing_text)
    existing_text.to_s.scan(/^## Revision v(\d+)/).flatten.map(&:to_i)
  end

  def next_revision_number(existing_text)
    (revision_numbers(existing_text).max || 0) + 1
  end

  # IO. Appends one entry to `<intent_dir>/revisions.md`, creating the file with its
  # documented header (matching templates/revisions.md's "# revisions.md" title line) if it
  # does not exist yet. NEVER overwrites or reorders a prior entry (append-only, intent 124's
  # own v3-corrects-v2-by-appending precedent). Returns the revision number written.
  #
  # Raises RevisionsWriter::WriteFailed on any IO error (permission, disk full, read-only
  # filesystem) so a caller can roll back a paired structural change rather than leave it
  # unrecorded (D14's "or refuse"). Never swallows an error silently.
  def append!(intent_dir, why:, rule:, prior_location:, change:, timestamp: Time.now.utc)
    path = File.join(intent_dir, "revisions.md")
    existing = File.exist?(path) ? File.read(path) : "# revisions.md\n\n"
    n = next_revision_number(existing)
    entry = render_entry(n, why: why, rule: rule, prior_location: prior_location,
                         change: change, timestamp: timestamp)
    File.write(path, "#{existing.chomp}\n\n#{entry}")
    n
  rescue StandardError => e
    raise WriteFailed, "could not append revisions.md at #{path}: #{e.message}"
  end

  class WriteFailed < StandardError; end
end
```

## 3b. Tests - new file `test/revisions_writer_test.rb`

```ruby
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
```

## Verify

`ruby -Itest test/revisions_writer_test.rb` green, then the full suite.
