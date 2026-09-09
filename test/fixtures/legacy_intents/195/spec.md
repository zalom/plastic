Tier: S
# Spec: Doctor-consistency roadmap, decision and release cut

## Problem

Plastic gates the front of the lifecycle with real hooks (create-gate, code-gate, lock-gate,
bash-gate) and trusts the back of it, everything after Exec, to prose an agent has to remember.
A routine 1.2.0 to 1.3.0 update ran the doctor and it came back with 1 failure and 10 warnings.
The root-cause sweep traced ten findings to that one shared cause, and found that two of the
doctor's own shipped repair paths were actively harmful, not just weak: the fix_hint for a
broken cross-store link would have deleted a valid link, and `provision-project-store` silently
wrote nothing while printing `OK`.

The batch's own blocker turned out to be an instance of the exact same disease. Closing intent
196 uncovered that the roadmap queue reader parsed only a `## Waves` heading, so every roadmap
written since owner ruling 145 renamed the grouping to `## Batches`, this one included, parsed
as zero entries, and `roadmap-next` silently reported `state: exhausted` instead of failing
loudly. The same session found finding 10 live: `end-intent`'s INDEX terminal move required an
em dash between id and title, so any INDEX line written with a plain hyphen, which is every
intent in this batch (187 to 196), was silently skipped while the script still committed and
exited 0.

Nine intents (187 to 194, 196) were scaffolded to close these gaps. They are now delivered and
merged. This intent, 195, does not do that work. It owns the batch's decision and the release
cut once the nine are confirmed delivered.

## Goals

- Confirm each of the nine collected intents (187 to 194, 196) is actually delivered, grounded
  in its own outcome.md, not just its plan, because this batch is specifically about tools that
  report success falsely.
- Record the doctor's real, current result honestly rather than assert a clean pass.
- Cut and publish the 1.4.0 release across all three version files, tagged, on the stable
  channel.
- Close the roadmap accurately: fix its stale Batch 4 checkbox for 194 and append a closing Log
  entry that states the true partial result, without rewriting the Goal section itself.
- Keep the pending dealintell Links repair an explicit open item, not silently folded into the
  release.
- Record the two mechanism-level lessons the batch taught as part of the delivered record, since
  they are the real yield of the work.
- Complete intent 195 once the above are true.

## Non-Goals

- No further code changes. All nine collected intents are already delivered and merged; this
  intent touches no scripts, hooks, or tests.
- Executing the dealintell Links repair (global 26, dealintell 3b, dealintell 15). It touches
  Completed intents and needs the owner's own one-time grant; this intent tracks it as an Open
  Question, it does not decide it.
- Closing the 41 legacy `signals_complete` gaps. They predate intent 93's outcome.md mandate and
  are advisory forever by design.
- Closing the 3 pre-convention `signals_complete` gaps. Their cause is unrelated to this batch
  and closing them is not this batch's job.
- Any of the follow-ups the nine intents recorded in their own outcome.md files (Enola
  reindex-at-close automation, wiring the safe Links projector into the End tail, folding
  `ProjectValidator` into doctor, narrowing `restore-intent-v1`'s Links reproject to one intent,
  correcting PLASTIC.md's `chain` bullet direction, and others). These belong to future intents,
  not this release decision.

## Approach

Verify before deciding. The nine collected intents claim delivery in the roadmap's own Batches
list; that claim is checked against each intent's own outcome.md, not the plan, because a batch
about tools that lie about their own success cannot let its own closing intent skip that check.
All nine show `disposition: delivered`. One inconsistency surfaced in that check: the roadmap
file's Batch 4 entry for 194 is still unchecked and marked "delivering", though 194's outcome.md
is delivered. That gets corrected as part of closing the roadmap, not silently left stale.

The doctor is then run live, read-only, from the plastic repo, rather than trusting the
roadmap's earlier log entry. The confirmed result is 1 failure and 2 warnings, not zero.
`hooks_match_registry` fails because the new `plastic-links-gate` hook exists in the repo and is
registered in `HookRegistry`, but has not reached `~/.claude/hooks` yet. That is not a defect;
it is exactly what this release, followed by a local update, resolves. `graph_links_projection`
warns on 3 cases (global 26, dealintell 3b, dealintell 15) that need a store repair touching
Completed intents. Intent 192's team already worked out the correct per-case fix: drop 3b's
three broken single-dash wikilinks (they resolve nowhere, are redundant with the parent chain,
and their meaning already survives in 3b's own Context prose), add the missing frontmatter edge
`3a.chain += ["15"]` for the one real relationship (a dry run of the new preserving projector
confirmed it keeps 15 rather than deleting it), and reproject global 26. None of that can run
without the owner's explicit one-time grant under the completed-intents-immutable rule, so it
stays open. `signals_complete` warns on 44 gaps: 41 are legacy and permanently advisory by
design, the remaining 3 are pre-convention and belong to neither this batch nor this intent.

Given that, the release proceeds without waiting on the two remaining warnings. All nine intents
are independently tested, reviewed, and merged; holding the release for a decision only the
owner can make would strand delivered, working code for no gain. The cut bumps all three version
files (package.json, plugin.json, marketplace.json) from 1.3.0 to 1.4.0, a minor bump because
the batch adds new user-facing surface (a new hook, new CLI tools, a new config-ask mechanism)
with no breaking change to any existing command, tags it, and publishes to the stable channel
with the latest dist-tag, matching the roadmap's own header ("Ships stable"). The roadmap file
is then updated: the 194 checkbox is corrected, a closing Log entry records the honest partial
result instead of a false zero-warnings claim, and the roadmap is marked closed. The Goal section
itself is not rewritten; it stays as the batch's original charter, and the Log carries the truth
of what was actually delivered. Intent 195 completes last.

Two lessons from the batch are recorded here because they are the actual yield of the work, not
an afterthought. First, every real fix in this batch worked by fixing a mechanism, not by
patching a list: 190's glob over `templates/*` beat a per-template allowlist test, 189's shared
store-discovery module beat a hardcoded two-store list, 191's four-bucket agent classifier beat
a two-name allowlist, and 196's shared grouping-heading matcher beat two private copies of the
same parsing logic. Second, in three of the nine intents the stated fix in the intent's own
brief was the wrong fix, and it was only caught because a team verified the claim before
building it: 189 found that the doctor's own fix_hint would have deleted the valid global
26 to ai-agents-resources:1 link, because unknown-store and genuinely-dead both classified as
`:dead`, and `:dead` means delete; 191's team overruled a coordinator steer with evidence,
because no `~/.plastic/agents` tree exists at doctor run time, so the originally suggested fix
would have silently passed in the field; 192 found the intent's own premise was half wrong,
PLASTIC.md forbids both hand-writing a Links line and auto-deleting one, and `project-links` was
itself violating the second half, so the doctor's fix_hint would have destroyed dealintell 15's
only record of a real relationship.

## Alternatives Considered

| Alternative | Not chosen because |
|---|---|
| Hold the release until graph_links_projection and signals_complete both reach zero | The remaining warnings need either an owner grant to touch Completed intents, or are advisory forever by design; holding the release would strand nine already delivered, tested intents for a decision this batch cannot make on its own |
| Execute the dealintell Links repair as part of this release | It touches Completed intents (3b, 15, global 26); the standing rule requires an explicit one-time owner grant before any such edit, and folding it in without that grant would break the very rule this batch protects |
| Ship a patch release (1.3.x) instead of a minor bump | The batch adds new user-facing surface (the links-gate hook, the restore-intent-v1 and validate-project CLIs, the config_asks mechanism), which the project's own versioning convention treats as a minor bump, not a patch |

## Decisions

- D1. This intent's deliverable is a decision and a release cut, not code; its acceptance
  criteria are scoped to the release cut and the roadmap's closure, never to code changes, which
  belong to the nine already-delivered collected intents.
- D2. The doctor's live result is verified firsthand before being written into this spec, rather
  than trusted from the roadmap's earlier log entry.
- D3. The roadmap's Goal ("zero failures and zero warnings other than the 41 legacy gaps") is
  honestly partially met. This spec states that plainly instead of claiming a clean pass.
- D4. `hooks_match_registry`'s failure is the expected pre-install state of the new
  `plastic-links-gate` hook, not a defect of this batch; it resolves once this release ships and
  the local install is updated.
- D5. `graph_links_projection`'s 3 warnings need a store repair touching Completed intents
  (dealintell 3b, 15, and global 26). Under the standing immutability rule this requires an
  explicit one-time owner grant, is not executed by this intent, and is carried forward as an
  Open Question.
- D6. `signals_complete`'s 44 gaps are out of this batch's scope: 41 are legacy and advisory
  forever by design, the remaining 3 are pre-convention and not this batch's job to close.
- D7. The two mechanism-level lessons the batch taught (fix the mechanism, not the list; verify
  a stated fix before trusting it) are recorded as part of this spec, because they are the real
  yield of the work.
- D8. The batch's own blocker (196) and the live-caught finding 10 (`end-intent`'s em-dash-only
  INDEX matcher) are named here as instances of the same disease class this batch was chartered
  to fix, not treated as unrelated incidental bugs.

## Acceptance Criteria

- [ ] All nine collected intents (187 to 194, 196) are confirmed delivered via their own
      outcome.md files, and that confirmation is recorded in 195's own outcome.md.
- [ ] The doctor is run live before the release and its real result (1 fail:
      `hooks_match_registry`; 2 warn: `graph_links_projection`, `signals_complete`) is recorded
      accurately, including why none of the three is zero.
- [ ] Version bumped from 1.3.0 to 1.4.0 across `package.json`, `plugin.json`, and
      `.claude-plugin/marketplace.json`; a git tag created; published to npm on the stable
      channel with the latest dist-tag.
- [ ] `doctor-consistency.md`: Batch 4's checkbox for 194 corrected from unchecked "- delivering"
      to checked "- delivered"; a closing Log entry records the true partial result instead of a
      zero-warnings claim; the Goal section itself is left untouched; the roadmap then marked
      closed.
- [ ] The dealintell Links repair (global 26, dealintell 3b, dealintell 15) is not executed as
      part of this release; it stays an explicit open item pending the owner's one-time grant.
- [ ] Intent 195's outcome.md records the two mechanism-level lessons the batch taught (fix the
      mechanism, not the list; verify a stated fix before trusting it), naming which intents
      demonstrated each.
- [ ] Intent 195 itself reaches Completed after the above are true.

## Open Questions

- Does the owner grant the dealintell Links repair? The proposal is written and held at intent
  192's `resources/repair-proposal--dealintell-3b-15.md`: drop dealintell 3b's three broken
  single-dash wikilinks, add the missing frontmatter edge `3a.chain += ["15"]` for the one real
  relationship, and reproject global 26. It touches Completed intents, so it needs an explicit
  one-time grant under the immutability rule. Until granted, `graph_links_projection` stays at
  warn and the doctor's Goal in the roadmap is not fully met.
