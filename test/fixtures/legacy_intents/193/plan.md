# Restore-to-v1 preserves the frontmatter graph Implementation Plan

> **For agentic workers:** Use `plastic-intent-executing` to implement this plan task-by-task.

**Goal:** Build `scripts/restore-intent-v1`, a tool that reverts a completed intent's prose to
an explicit v1 git ref while preserving its `sources`/`chain` frontmatter graph as a
target-resolved union, and document the procedure so it is never hand-run again.

**Architecture:** A thin CLI shell (`scripts/restore-intent-v1`) does discovery, git IO, and
reporting; a pure library (`scripts/lib/restore_intent_v1.rb`) does the union + target-resolution
math, reusing `scripts/lib/graph_rebuild.rb`'s `GraphRebuild.resolve_ref` and
`scripts/lib/frontmatter_writer.rb`'s `FrontmatterWriter.rewrite_arrays` verbatim. Dry-run is the
default; `--apply` writes, reprojects `## Links` via `scripts/project-links` (called, not edited),
and appends a `revisions.md` entry. Two doc edits (`PLASTIC.md`, `skills/intent-creating/SKILL.md`)
make the procedure discoverable so an agent is pointed at the tool instead of improvising a
hand-run `git checkout`.

**Tech Stack:** Ruby (stdlib only: `yaml`, `date`, `time`, `fileutils`, `open3`, `tmpdir` in
tests), Minitest, git as a subprocess.

**Intent:** 193: Restore-to-v1 preserves the frontmatter graph

**Tier:** M. One consolidated `actions/ACTION_1.md` carries the whole ordered delivery.

---

## Code location (hard constraint)

All code changes land ONLY in the worktree:
`/Users/zlatko/apps/personal/plastic/.claude/worktrees/193--restore-to-v1-preserves-graph`
(branch `plastic/193--restore-to-v1-preserves-graph`, off main `a160841`). Use absolute paths for
every file operation. Never touch the main checkout (`/Users/zlatko/apps/personal/plastic`) or
any other worktree.

**Forbidden to edit** (intent 192 owns these concurrently in this session): `scripts/project-links`,
`scripts/lib/links_projection.rb`, `hooks/create-gate`. Call `scripts/project-links` as a
subprocess only.

## Task Map

1. Pure library `scripts/lib/restore_intent_v1.rb`: union + target resolution + frontmatter
   apply, unit-tested directly (no subprocess, no git).
2. CLI shell `scripts/restore-intent-v1`: argv parsing, git extraction of v1, dry-run report,
   `--apply` write path, `project-links` reprojection call, `revisions.md` append, maintenance-lock
   reminder print.
3. The proof pair (the heart of the plan): a hermetic git fixture shaped like the real 124/131
   incident; one test drives the OLD whole-file-revert behavior and shows the backlink lost, the
   other drives the NEW tool over the identical fixture and shows it preserved.
4. Target-resolution tests: a dead v1 edge is dropped and reported; a dead v1 edge combined with
   a live current edge resolves to exactly the live edge. Also: dry-run (no `--apply`) makes zero
   filesystem writes, `checklist.md`/`outcome.md`/`spec.md`/`plan.md` revert to exact v1 bytes
   (mirroring the real `60a51bf`'s four touched files), and `## Links` reflects the preserved
   graph after an applied restore, asserted directly against the expected rendered text.
5. Fail-loud tests: unresolved `--at`, unresolved intent id, unparseable v1 frontmatter, each
   exits non-zero AND leaves the on-disk file byte-for-byte unchanged.
6. Two documentation edits: `PLASTIC.md` (Terminal immutability subsection) and
   `skills/intent-creating/SKILL.md` (Decide Branch vs Root section).
7. Full suite green (`bin/test`), em-dash guard on the diff, commit.

See `actions/ACTION_1.md` for the full ordered steps with exact code, file paths, and commands.

## Notes

- `~/.plastic` is the owner's production data and this exact bug class already destroyed part of
  it once. No test ever touches it; every test builds its own `Dir.mktmpdir` git repository (the
  `test/new_intent_test.rb` `git init` pattern), and drives fixture intents through the real
  `scripts/new-intent` subprocess so I1 backlinks are written the same way production writes them.
- The Links assertion in tests is direct (compute and compare the expected rendered body text),
  never coupled to `scripts/project-links`'s CLI surface, which intent 192 is rewriting
  concurrently. The TOOL itself still calls `project-links` for real at `--apply` time.
- No em-dashes in any new code comment, doc line, or commit message. Hyphens only.
- `revisions.md` writing and the lock-reminder print only happen on `--apply`, never on a
  dry-run.
