---
id: "195"
intent: "Roadmap: the doctor-consistency batch - own the order, the batching and the release cuts for the eight fixes surfaced by the 2026-07-13 doctor root-cause sweep (equip the repo with Enola; enforce the End-tail disarm; make the graph tools discover stores from projects.yml; ship every template and self-check project spawn; teach doctor about the consultation agents; guard hand-authored Links; make restore-to-v1 preserve the graph; let a release announce its own config question); the sweep found one shared cause behind almost all of them: Plastic gates the FRONT of the lifecycle with real hooks (create-gate, code-gate, lock-gate, bash-gate) and trusts the BACK of it to prose an agent must remember, so everything that rotted rotted after Exec was over, and two shipped repair paths were actively harmful (the doctor's own fix_hint would have deleted a valid cross-store link, and provision-project-store silently no-ops while printing OK); this intent owns the batch decision and the cuts, NOT the delivery of the collected intents"
sources: []
chain: ["196"]
created: 2026-07-13
author: claude-code
tags: ["plastic", "roadmap", "doctor", "consistency", "enforcement", "project-plastic"]
---

## Intent
Roadmap: the doctor-consistency batch - own the order, the batching and the release cuts for the eight fixes surfaced by the 2026-07-13 doctor root-cause sweep (equip the repo with Enola; enforce the End-tail disarm; make the graph tools discover stores from projects.yml; ship every template and self-check project spawn; teach doctor about the consultation agents; guard hand-authored Links; make restore-to-v1 preserve the graph; let a release announce its own config question); the sweep found one shared cause behind almost all of them: Plastic gates the FRONT of the lifecycle with real hooks (create-gate, code-gate, lock-gate, bash-gate) and trusts the BACK of it to prose an agent must remember, so everything that rotted rotted after Exec was over, and two shipped repair paths were actively harmful (the doctor's own fix_hint would have deleted a valid cross-store link, and provision-project-store silently no-ops while printing OK); this intent owns the batch decision and the cuts, NOT the delivery of the collected intents

## Context
Intent 195 is a decision intent, not a code intent, because the batch needed a place at the
end of the lifecycle to verify the nine collected intents' claims, record the doctor's real
result, and make the release call. Plastic gates the front of the lifecycle with real hooks
(create-gate, code-gate, lock-gate, bash-gate) but trusts the back of it, everything after
Exec, to prose an agent has to remember; the root-cause sweep found that everything that
rotted, rotted after Exec was over. A routine 1.2.0 to 1.3.0 update ran the doctor and it came
back with 1 failure and 10 warnings, and tracing those ten findings led to that one shared
cause. Nine intents (187 to 194, 196) were scaffolded to fix them. 195 owns the batch's
decision and the release cut, not the delivery of those nine.

### Decisions
- D1. This intent's deliverable is a decision and a release cut, not code; its acceptance
  criteria are scoped to the cut and the roadmap's closure, not to code, which belongs to the
  nine collected intents.
- D2. The doctor's live result is verified firsthand, not trusted from the roadmap's earlier
  log entry.
- D3. The roadmap's Goal (zero failures and zero warnings other than the 41 legacy gaps) is
  honestly only partially met, stated plainly rather than claimed as a clean pass.
- D4. hooks_match_registry's failure is the expected pre-install state of the new
  plastic-links-gate hook, not a defect; it resolves once this release ships and the local
  install updates.
- D5. graph_links_projection's 3 warnings need a store repair touching Completed intents
  (dealintell 3b, 15, global 26); under the immutability rule this needs an explicit one-time
  owner grant, is not executed here, and is carried as an Open Question.
- D6. signals_complete's 44 gaps are out of this batch's scope: 41 are legacy and advisory
  forever by design, the other 3 are pre-convention and not this batch's job.
- D7. The two mechanism-level lessons the batch taught are recorded here as the real yield of
  the work.
- D8. The batch's own blocker (196) and the live-caught finding 10 (end-intent's em-dash-only
  INDEX matcher) are named as instances of the same disease class this batch was chartered to
  fix, not unrelated bugs.

## Outcome
Delivered the doctor-consistency batch: nine intents merged, released as v1.4.0, and the doctor went from 1 failure and 10 warnings to zero failures. The two remaining warnings are named honestly rather than papered over: a Links repair awaiting the owner's grant because it touches completed intents, and 44 completeness gaps that are advisory by design.

## Insights
(observations captured throughout — raw material for future intents)

## Links
- [[196--roadmap-tooling-speaks-batches|Roadmap tooling must speak Batches, not Waves: the shared queue reader (scripts/lib/roadmap_queue.rb:115, section_body(text, "Waves")) parses only a '## Waves' section, but owner ruling 145 renamed the grouping to '## Batches' and the roadmap template and skills followed; every roadmap written since that ruling (doctor-consistency, intelligence) therefore parses as zero entries, so roadmap-next returns state=exhausted with an empty dispatchable_queue and both the auto loop and plastic-roadmap-continuing silently see nothing to do, while the three older Waves roadmaps still parse, which is why it went unnoticed; same class as the rest of the 195 batch (the tool silently disagrees with the convention instead of failing loudly); teach the reader and every sibling roadmap parser/writer (roadmap-savepoint, the roadmap skill's file-format reference, the roadmap template) to accept '## Batches' as the canonical heading while still reading legacy '## Waves' roadmaps, with a regression test per heading and a loud parse error when a roadmap has neither; do not rename the old roadmaps (145 ruling); this is the blocking issue for the whole 195 delivery, so it runs first]]
