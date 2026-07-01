# revisions.md

<!--
FORM reference. A live revisions.md exists in an intent directory ONLY when structural
maintenance actually happened. It is never scaffolded at intent birth, it carries no
placeholder sentinel, and its mere presence signals that this intent underwent structural
(not conceptual) change.

Rules:
- Append-only. Newest entry at the BOTTOM. Never edit or reorder past entries.
- One entry per relocated item (one section, one file, or one ref per entry).
- Move-and-record: remove the misplaced thing from its artifact and preserve it IN FULL
  here. Never rewrite, summarize, or reinterpret delivered meaning. A change to delivered
  meaning is a new intent, not a revision.
- Header form: "## Revision vN - YYYY-MM-DD-HH:MM" (N increments by one per entry).

Fields:
- Why:            one sentence naming the broken rule, ending with "[rule: <tag>]".
- Prior location: the artifact plus the section or path the content came from.
- Content held:   the verbatim removed content, as an indented block (block form), OR
- Change:         a one-line "removed X (before: ... -> after: ...)" for a frontmatter
                  edit, used instead of a Content held block.

Stray file: embed the file's full content as the Content held block and delete the
original; Prior location names the filename. revisions.md is the single container.

Violation-tag catalog (starter set; free-text tags are allowed):
- unsanctioned-section : a top-level section the sanctioned-section rule now rejects
- phantom-section      : a section referenced but not present or not sanctioned
- stray-file           : a file that does not belong in the intent directory
- dangling-ref         : a link or reference to something that no longer exists
- broken-chain         : a chain frontmatter edge to an intent that no longer exists
- broken-source        : a sources frontmatter edge to an intent that no longer exists
- misplaced-content    : content that belongs in a different artifact or section

The examples below show the three variants. Delete them when you write the first real
entry; keep the "# revisions.md" title line above.
-->

## Revision v1 - 2026-06-30-14:35
- Why: unsanctioned top-level section left over from an early draft [rule: unsanctioned-section]
- Prior location: intent.md - ## Scope
- Content held:

  ## Scope
  <the full content that was removed, verbatim>

## Revision v2 - 2026-06-30-15:02
- Why: chain edge to an intent that no longer exists [rule: broken-chain]
- Prior location: intent.md frontmatter - chain
- Change: removed "99x"  (before: ["4a1a", "99x"]  ->  after: ["4a1a"])

## Revision v3 - 2026-06-30-15:20
- Why: a stray notes file that does not belong in the intent directory [rule: stray-file]
- Prior location: notes-old.md
- Content held:

  <the full content of notes-old.md, verbatim; the original file is then deleted>
