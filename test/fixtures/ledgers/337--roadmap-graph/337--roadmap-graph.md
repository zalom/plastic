---
id: "337"
intent: "G4 of the graph-ready plan (intent 327, Batch 3, needs G3 (336)): Roadmap graph. Roadmap graph: `## Graph`, cycle check at read, rendered tree (melds 327a), computed `## Batches` with no hand pins (D42), `graph.md` and roadmap files written through the rename writer (C5), migration of live roadmaps, INDEX rendered from ledgers."
sources: ["327"]
chain: []
created: 2026-09-07
author: claude-code
tags: ["project-plastic", "graph-ready", "batch-3", "g4"]
---

## Intent
G4 of the graph-ready plan (intent 327, Batch 3, needs G3 (336)): Roadmap graph. Roadmap graph: `## Graph`, cycle check at read, rendered tree (melds 327a), computed `## Batches` with no hand pins (D42), `graph.md` and roadmap files written through the rename writer (C5), migration of live roadmaps, INDEX rendered from ledgers.

## Context
G4 of the graph-ready plan (intent 327). The roadmap is the only place a cross-intent edge
lives, and today only one live roadmap out of nineteen carries a `## Graph` section at all.
Batches are still hand-authored headings that a human keeps in order, the reading order of a
roadmap is a list rather than a drawing, and INDEX.md status is maintained by hand beside the
savepoint ledgers that already know the truth.

Batch 1 and Batch 2 built the machinery this intent projects onto the roadmap scope.
`GraphEdges` (intent 334) already parses the `needs` grammar and returns a cycle as a whole
path, and 327 C1 ruled that an intent's `graph.md` and a roadmap's `## Graph` share that one
parser unchanged. `ReadySet` (intent 336) already computes topological batches, the critical
path by hops, and downstream hop counts as pure functions over an edge hash. `AtomicWrite`
(intent 334) is the temp-plus-rename writer C5 requires. `RoadmapQueue` already reads a
roadmap's `## Graph` when one exists and falls back to wave order when it does not, and it
already refuses to compute a frontier on a cyclic graph.

What is missing is the roadmap-facing half: one reader that turns a roadmap file into the same
shape the node scope uses, a tree rendering (intent 327a, melded here by 327's plan), rendered
`## Tree` and `## Batches` sections written through the rename writer, a migration that gives
the eighteen graphless roadmaps a starting `## Graph`, and INDEX as a projection of the
ledgers rather than a second hand-kept truth.

Intent 327a is the branch that owns how the graph is shown: an indented tree with box-drawing
branches where one node may have many children and a shared dependency is drawn once where the
branches join, marking the critical path and the ready set, plain text first with color only
through the fail-open display hook. It is melded into this intent rather than delivered
separately.

### Decisions
- D1 One roadmap-scope model, `RoadmapGraph`, built on `GraphEdges` for the edge grammar and
  the cycle walk and on `ReadySet` for batches, critical paths, and downstream hops. No second
  edge parser, no second topological sort, no second cycle check anywhere in this intent
  (327 C1, D41). Amended at the plan review (A7): `RoadmapQueue#frontier_for` is refactored onto
  `RoadmapGraph` and its duplicate roadmap-graph reader, topological sort, unnamed-entry meld,
  and unlisted-id report are deleted. Leaving them would make D1 false the day it shipped: the
  screens would render batches from `ReadySet` while `roadmap-next` dispatched from a second
  sort that agrees only by luck.
- D2 The cycle check runs at read, on every path that can return a tree, a batch list, or a
  frontier, and it reports the whole cycle path. A cyclic roadmap renders the cycle instead of
  batches; it never renders a partial or invented order, and the writer refuses it (melds 241,
  327's ranked risk list).
- D3 `## Tree` and `## Batches` are rendered sections, never authored. The writer replaces
  exactly those two sections and leaves `## Goal`, `## Graph`, `## Log`, and every other
  section byte-identical. Rendering twice over the same input is a no-op on disk.
  Amended at the plan review (A1, A2): the writer preserves every byte it cannot parse.
  Non-entry prose inside the grouping section stays anchored to the batch heading it follows,
  and an entry line the canonical grammar cannot parse is carried verbatim into the batch its
  file position implies. Twenty-one such lines and one load-bearing owner paragraph exist on
  the live roadmaps today; a regroup that rebuilds the section from parsed entries deletes them.
- D4 No hand batch pins (327 D42). A batch is a topological layer of `## Graph` and its heading
  is `### Batch N`. The 327 report's "hand pins marked" wording is superseded by D42, which is
  the later owner ruling. An entry a batch lists that `## Graph` does not name is melded in as
  needing nothing, so a partly migrated roadmap still renders rather than dropping work.
- D5 Every roadmap file write in this intent goes through `AtomicWrite` (C5). No roadmap is
  truncated in place, and the interrupted-rename case is tested through the injected renamer.
- D6 Migration is derive-then-write, idempotent, and never overwrites an existing `## Graph`.
  The derived edge set is the conservative reading of a hand-ordered batch list: every entry of
  batch N needs every entry of batch N-1. The owner edits the edges afterward; the migration
  only removes the blank-page problem.
- D7 INDEX is a projection of the intent savepoint ledgers, and the ledger wins where the
  ledger speaks. Restated at the plan review (A4): 63 of 451 intents in the plastic store have
  no `savepoint.md` at all and 59 more stop before a `Done` line, so a literal "the ledger
  always wins" would demote 103 Completed intents to Active on the first `--write`. An intent
  whose ledger is absent or silent keeps the status INDEX already carries. The projection is
  computed and compared by default and reported as drift; writing INDEX.md requires an explicit
  flag. The store's spine is never rewritten as a side effect of rendering a roadmap.
- D8 Plain text is the floor. The tree renderer emits no escape codes at all; color reaches a
  terminal only through the existing fail-open display hook, per the cross-harness TUI ruling.
- D9 The tree is drawn from `## Graph` edges only, never from `sources`, `chain`, or any
  lineage field (327a). A roadmap with no graph gets no tree, not a guessed one.
- D10 The migration and the INDEX writer are additive commands, not new behavior inside
  `roadmap-next` or `end-intent`. A caller that does not ask for a render sees the bytes it
  sees today.
- D11 Within a batch, entry order is the roadmap's own file order, and the injected ranker is
  the only thing that may reorder it (plan review A8). The layer sort in `ReadySet.batches` and
  in `RoadmapQueue#topological_layers` is lexical, which on one live roadmap flips the auto
  loop's rank 1 from `5` to `2`. A computed batch must not quietly become a ranking decision.
- D12 A roadmap carrying the legacy `## Waves` grouping heading renders into that heading in
  place (plan review A3). The writer never adds a `## Batches` section beside a `## Waves` one:
  `RoadmapSavepoint.grouping_heading` finds `Batches` first, so doing that would repoint every
  reader at the generated section and orphan the human's. Seven live roadmaps use `## Waves`.
- D13 `migrate` refuses a file carrying a heading that begins `## Graph` but is not exactly
  `## Graph` (plan review A9). One live roadmap has such a heading, a thirty-line superseded
  owner note, and a migration that ignored it would leave the file with two graph headings.
- D14 No new excludable doctor rule key. `RuleCatalog::EXCLUDABLE_CHECKS` is pinned verbatim by
  a test, `savepoint_operational` already reports the missing and silent ledgers, and the new
  finding would repeat roughly 103 of them. The drift finding is emitted from the existing
  `check_done_signals` in `scripts/doctor.rb` and scoped to what `savepoint_operational` does
  not cover: an intent whose ledger does carry a terminal line that disagrees with INDEX
  (plan review A6). `scripts/lib/doctor_core.rb` is the installation doctor and is not touched.
- D15 A need that is abandoned, or that names an entry which can never be delivered, is
  reported as a dead end rather than silently blocking every entry behind it (plan review A10).
  `ReadySet.dead_end?` already does this at node scope; the roadmap scope gets the same answer.
- D16 Archived roadmaps are out of scope. Twenty-eight files sit under `roadmaps/archived/`;
  `RoadmapQueue` never reads them and r1 never writes them (plan review B6).
- D17 The INDEX writer touches only the four status sections. `## Clusters` and `## Relocated`,
  which together hold most of the plastic store's INDEX, are carried through byte-identical
  (plan review B5).

## Outcome
(the result — implementation details, deliverables)

## Insights
(observations captured throughout — raw material for future intents)
2026-09-10T07:06:10Z · Exec · plastic-executor (autonomous) — IndexProjection.analyze needed an index_path: override (defaulting to store_path/INDEX.md) because the real Plastic layout keeps INDEX.md one level above store/, not co-located with intent dirs; the n5 unit tests (flat, self-authored fixtures) didn't catch this until n6 wired the real CLI and doctor.rb callers.
2026-09-10T07:06:11Z · Exec · plastic-executor (autonomous) — GraphFile.replace_or_append_section always inserts its own single blank-line separator before a non-empty tail; a caller must rstrip its own regrouped/rendered body before passing it in, or repeated writes accumulate one extra blank line per render (found by RoadmapRender's own idempotency test, row 3.9).
2026-09-10T07:06:11Z · Exec · plastic-executor (autonomous) — screen_width_test.rb's leg-2 pinned line numbers shift predictably: inserting new require_relative lines near the top of report_screen.rb shifted all five pinned sites by the same delta; the new roadmap_tree_block method itself, placed below every pinned site and written with zero array-append (<<) syntax, added no new leg-2 site and shifted nothing else.
2026-09-10T07:06:11Z · Exec · plastic-executor (autonomous) — RoadmapMigration.derive found a real hazard worth flagging generally: an id repeated across two non-adjacent batches in a graphless roadmap derives a self-need (id needs itself) unless explicitly excluded, because the naive 'batch N needs every id of batch N-1' rule doesn't know an id also reappears later; fixed by rejecting the subject's own id from its derived needs.
2026-09-10T13:37:19Z · Exec · lead:337 — A roadmap entry line the canonical grammar cannot parse is invisible to the entry parser but visible to RoadmapMigration, so the derived graph can name an id no batch lists. Wave order tolerated such a line by skipping the batch; the graph blocks everything behind it. D15 holds - the payload names the id and the reason - but the fix is the data, not the code.
2026-09-10T13:37:19Z · Exec · lead:337 — intelligence.md entry 42 carries the status token 'deferred', which the grammar does not define, so 147 moved from dispatchable to blocked when the roadmap gained a graph. Mapping 'deferred' onto a canonical status changes what the auto loop does with 42 and needs an owner ruling.
2026-09-10T13:37:19Z · Exec · lead:337 — A tree test that reads with lines.index sees only the first occurrence, so it cannot catch a node drawn twice; a substring count is fooled by a converging reference on the join line. Counting drawn identities - box prefix and critical marker stripped, up to the first space or bracket - is the assertion shape that catches a duplicated fan-in node.
2026-09-10T13:37:19Z · Exec · lead:337 — index-projection reads no id out of the wiki-link INDEX form the mihradesign store uses (- [[69]] slug), so its compare report comes back complete on both sides. Drift is still correct, because drift compares only ids present on both sides.
2026-09-10T13:37:19Z · Exec · lead:337 — On the day INDEX became a projection of the savepoint ledgers, drift was zero in all six project stores: not one intent's own ledger contradicted the status INDEX carried for it.

## Links
- [[327--graph-of-work-under-the-roadmap|Research and thinking: the graph of work under the roadmap name. Roadmap stays the human-facing word; underneath, intents carry a dependency graph: the existing dashboard ready rule (all sources completed) wired into the roadmap queue, an after edge for sibling order, computed batches with hand batches as override, a cycle check at creation, supersedes edges and a computed lineage for how an intent was reshaped (D20), and archive as a view. Ties 224 (research, done), 241 (repair and guard), 282 (roadmap graph research), 132 (archive dir) into one design; rulings D15, D16, D17, D20, D24 from 323]]
