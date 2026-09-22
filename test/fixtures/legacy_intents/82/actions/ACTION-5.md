# ACTION-5 — PLASTIC.md `## Insights` codification

Implements acceptance criterion 7 (PLASTIC.md's `## Insights` documentation gains the prefix
format, the definition of an insight, and the bg/dispatched-agent delivery rule). Pure user-facing
doc edit; depends on the helper name (`insight-append`) and the report-contract field from ACTION-4.

## Where
Code worktree: `/Users/zlatko/apps/personal/plastic/.claude/worktrees/82--`
- EDIT: `PLASTIC.md` — the `## Insights` paragraph inside `## Lifecycle Stages` (the paragraph that
  currently starts ``## Insights` — append-only work log captured throughout ALL stages...``,
  around line 82)

## What to change
Expand the existing `## Insights` paragraph (keep the append-only / newest-at-bottom rule it
already states) to add:
1. **The definition of an insight.** A durable discovery surfaced at ANY stage (What/Why/How/Exec):
   novel, or old-but-newly-relevant, kept for later reads. Frame it as the most interesting residue
   of the intent.
2. **The entry format.** Every entry leads with `{utc-iso8601} · {stage} · {author}`, e.g.
   `2026-06-24T08:13:05Z · Why · plastic-brainstorming (autonomous)`. The UTC ISO8601 timestamp (to
   the second, trailing `Z`) matches the savepoint ledger exactly, so the store has one timestamp
   convention. State plainly that this per-entry PREFIX is not prepending the entry: entries stay
   append-only, newest at the bottom.
3. **The blessed write path.** Use the `insight-append` helper
   (`scripts/insight-append <intent_dir> <text> --stage S --author A`), which formats the prefix,
   validates it, and appends at the bottom. Hand-editing is an escape hatch; the helper is the
   default so format drift cannot creep in.
4. **The bg / dispatched-agent delivery rule.** Background sessions and dispatched sub-agents do not
   write the insight themselves: they carry each nugget home in the completion report's `insights:`
   field, and the orchestrator (or any agent that can write the file) persists it via the helper. A
   session that cannot write the intent file still returns its report, so the insight survives.

## Constraints
- PLASTIC.md is user-facing: NO em-dashes, no AI tell-tales. Use a hyphen. (Existing copy in this
  file already uses hyphens; match that voice.) Keep it terse and in the file's existing style.
- The `·` separator in the documented format is the literal middle dot, matching the helper output.
- Do not touch the savepoint paragraph except to note (if natural) that the two ledgers share the
  timestamp convention; no behavior change to the ledger.

## Verification
```
cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/82--
grep -n "utc-iso8601\|insight-append\|insights:" PLASTIC.md
grep -n " — \|—" PLASTIC.md   # confirm no em-dash was introduced in the edited lines
ruby bin/test
```
The format string, the helper name, and the delivery field appear; the em-dash check shows no new
em-dash in the edited region; the full suite stays green.
