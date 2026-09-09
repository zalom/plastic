# ACTION_7 - store curator: tool-enforced receipt contract + detect-lock/branch-merge doctrine

Covers the curator's share of spec.md AC7 (the fourth writer named alongside project-links,
rebuild-graph, restore-intent-v1) and the "Plan where this lives" half of the maintenance
mechanism (spec.md task 4 in the dispatch brief). The curator is agent-driven (an LLM
following documented steps via `Edit`/`Write`/`Bash`), not a Ruby script, so "tool-enforced"
here means the AGENT DEFINITION states the contract as an unconditional MUST with no
code-path that skips it, exactly as `restore_intent_v1.rb` leaves no code path that writes a
graph change without also calling `append_revision`. There is no Ruby to unit-test here; the
existing "test" surface for a skill is its eval file (`skills/store-curating/evals/evals.json`),
extended with one new eval.

Discovery citation: `agents/plastic-intent-curator.md`'s current step 6 (move-and-record) is
ALREADY documented - this action tightens it into an explicit refuse-without-a-receipt
contract and adds the maintenance-eligibility check that does not exist there today (this
agent currently has no lock-check or branch/merge step at all; it assumes it is always
operating inside its own already-locked delivery session).

Files: `agents/plastic-intent-curator.md`, `skills/store-curating/SKILL.md`,
`skills/store-curating/evals/evals.json` (all inside the worktree).

## 7a. `agents/plastic-intent-curator.md` - tighten step 6 into a refuse-without-receipt contract

Current step 6 (verbatim, `agents/plastic-intent-curator.md`, "How You Work" list):
```
6. Structural maintenance is move-and-record: remove the misplaced section, file, or ref from its artifact, then create or append `revisions.md` in that intent directory (copy the FORM from `~/.plastic/templates/revisions.md`). One entry per relocated item, newest at the bottom: a `## Revision vN - YYYY-MM-DD-HH:MM` header, a one-sentence `Why` ending with `[rule: <tag>]`, `Prior location`, and either `Content held` (verbatim) or a one-line `Change` for a frontmatter edit. For a stray file, embed its full content and delete the original. The violation-tag catalog is canonical in PLASTIC.md.
```

Target (same numbered position, replaces the paragraph above):
```
6. Structural maintenance is move-and-record, and it is NEVER done without its receipt: remove the misplaced section, file, or ref from its artifact, then create or append `revisions.md` in that intent directory (copy the FORM from `~/.plastic/templates/revisions.md`) IN THE SAME PASS as the edit. If you cannot write `revisions.md` for any reason (permissions, a read-only path), you MUST NOT make the structural edit either - report the blocker instead of leaving an unrecorded change (this mirrors the tool-side rule: project-links, rebuild-graph, and restore-intent-v1 refuse rather than write a change with no receipt; you hold yourself to the same rule by hand). One entry per relocated item, newest at the bottom: a `## Revision vN - YYYY-MM-DD-HH:MM` header, a one-sentence `Why` ending with `[rule: <tag>]`, `Prior location`, and either `Content held` (verbatim) or a one-line `Change` for a frontmatter edit. For a stray file, embed its full content and delete the original. The violation-tag catalog is canonical in PLASTIC.md. A graph edit must move TOWARD ground truth (drop a dangling/false edge, add a reciprocity-forced or documented-real one) and must NEVER invent a relationship - "might be related" is never a valid `[rule:]` reason (PLASTIC.md > WORK vs MAINTENANCE).
```

## 7b. `agents/plastic-intent-curator.md` - new step 6a: maintenance eligibility (detect-only lock, branch-and-merge)

Insert immediately after step 6 (before the existing step 7 "Report what you changed"),
renumbering step 7 to step 8:
```
7. Before performing structural maintenance on ANY intent that is NOT the one your own session is currently delivering under its own held delivery lock, you must:
   a. Check the target's lock freshness: `ruby ~/.plastic/scripts/plastic-lock status --intent-dir <target-intent-dir>` and read the `lock_fresh` field of its JSON output. If `true`, DEFER: make no edit to that intent, and report it as skipped (an active delivery is in progress). This is DETECT-ONLY - you never acquire, create, or hold any lock of your own for maintenance (PLASTIC.md > WORK vs MAINTENANCE; there is exactly one lock in Plastic, the delivery lock).
   b. Require a clean store working tree before starting: `git -C ~/.plastic status --porcelain` (or the project store's own root, if not global) must be empty. If it is not, STOP and report the dirty paths rather than risk sweeping an unrelated concurrent change into your own commit; do not proceed until the tree is clean.
   c. Create a fresh branch from the current tip of that repo's main: `git -C <repo-root> checkout -b maintenance/curator-<UTC-timestamp> main`.
   d. Make the scoped edit plus its `revisions.md` receipt (step 6 above), touching nothing else.
   e. Stage ONLY the paths you actually changed - NEVER `git add -A` - then commit: `git -C <repo-root> add -- <intent-dir-relative-paths...> && git -C <repo-root> commit -m "..."`.
   f. Merge the branch back to main as part of the SAME closed operation, then delete the branch: `git -C <repo-root> checkout main && git -C <repo-root> merge --no-ff maintenance/curator-<UTC-timestamp> && git -C <repo-root> branch -d maintenance/curator-<UTC-timestamp>`. Never leave the change stranded on an unmerged branch.
   This entire step 7 does not apply when you are running as part of your OWN session's normal end-of-delivery close (the existing steps 4-5 above, which already run inside that session's own held lock and are committed by `end-intent`'s own scoped `store_commit`, not by this step).
```

## 7c. `skills/store-curating/SKILL.md`

This skill file currently only dispatches to the agent and restates its lifecycle-close duties
(outcome.md authoring, calling `plastic-intent-ending`); it does not restate step 6/7's
maintenance mechanics (correctly - "Never restate those one-liners here" is the file's own
existing discipline for the close steps). Add one short paragraph after the existing
numbered list, naming the new capability so a caller (doctor's fix-all router, ACTION_11) knows
this skill is the maintenance dispatch target for a structural finding:
```

## Maintenance dispatch (intent 197)

When invoked to fix a structural finding on an intent OTHER than one currently being delivered
(for example, from `/plastic-doctor`'s fix-all routing), the `plastic-intent-curator` agent
follows its own step 7: it detects (never acquires) the target's delivery lock, requires a
clean working tree, and performs the fix on a fresh branch merged back to main as one closed
operation, with an append-only `revisions.md` receipt in the same pass as the edit. See
`agents/plastic-intent-curator.md` for the exact mechanics.
```

## 7d. `skills/store-curating/evals/evals.json` - one new eval

Add a second entry to the `"evals"` array (after the existing id `1`), matching the file's own
shape:
```json
    {
      "id": 2,
      "scope": "behavior",
      "set": "validation",
      "prompt": "The user says: intent 26 (Completed) has a stale ## Links comment that contradicts its own real chain edge; fix it. Intent 26 is NOT the intent currently being delivered by this session.",
      "expected_output": "Before editing intent 26, checks its delivery lock freshness (plastic-lock status --intent-dir, reading lock_fresh) and defers if fresh; requires a clean store working tree; creates a fresh maintenance branch off main; makes the scoped edit AND appends a revisions.md receipt in the same pass, refusing the edit if the receipt cannot be written; stages only the changed paths (never git add -A); merges the branch back to main and deletes it before reporting done.",
      "files": [],
      "assertions": [
        {
          "type": "human",
          "check": "agent file states detect-only lock check, clean-tree precheck, branch-and-merge-back, and refuse-without-receipt as an unconditional sequence for maintenance on a non-current intent",
          "observed": "agents/plastic-intent-curator.md step 7 covers all five sub-steps (a-f) exactly as asked",
          "result": "pass"
        }
      ]
    }
```

## Verify

No Ruby test suite covers this action (prose/skill files only). Verify by re-reading the
edited files for internal consistency (numbering, no duplicate step 7/8) and running the full
Ruby suite to confirm nothing else regressed (these files are not `require`d by any test).
