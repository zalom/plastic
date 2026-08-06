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
  # (plastic-conventions > references/maintenance-and-revisions.md; templates/revisions.md).
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
