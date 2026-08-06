# Knowledge Graph

This chapter holds the linking doctrine from Frontmatter and the branch-vs-root directory semantics from Directory Naming.

- `sources` (formative, must-load, acyclic) and `chain` (forward + relational, lighter,
  may cycle) form the directed knowledge graph. Reciprocity is one-directional: every
  `sources` edge has a reciprocal `chain` entry (I1), but `chain` may carry relational
  entries with no reciprocal `sources` (I2), so the graph is not strictly symmetric.

- `## Links` (I5) is the human-readable projection of the graph. It mirrors the
  frontmatter exactly: every entry is `- [[id--slug|<target's full intent: text>]]`, a
  clickable `id--slug` wikilink target with the target intent's full `intent:` text as the
  label (cross-store targets render `- [[store:id--slug|<target's full intent: text>]]`).
  Ordering is mandatory: all `sources` first (top), then all `chain`, frontmatter order
  preserved within each group. Sources never appear at the end. No source/chain tags, no
  sub-grouping. An intent with empty `sources` and `chain` carries the empty-state comment.
- `## Links` is a DERIVED view, not a place to author links (Convention over Configuration).
  It equals the projection of `sources` (first) then `chain`. Never hand-write or hand-edit a
  `## Links` line, and never auto-delete one. The edge lives in the frontmatter graph; the
  section is regenerated from it (doctor `graph_links_projection` enforces this identity). To
  add a link, add the frontmatter edge, then reproject.

- Links are decided by CONTEXT INFLUENCE, not by shared files, shared symbols, or a topic
  similarity score. The question is whether one intent's context actually informed another.
  Three tiers:
  - **sources:** the foundational context that shaped this intent's creation (a split, an idea
    born during development, a merge). Earns an edge.
  - **chain:** the context that materially helps DELIVER this intent. This is a HIGH bar: only
    the genuinely delivery-moving intents, not everything in the same area. Earns an edge,
    reflected in `## Links`.
  - **tags:** a loose theme grouping for search. NOT a link. A shared tag is a door INTO the
    store (filtered discovery), not a pathway BETWEEN two notes.
  Judging influence is an agent's call, made by reading the candidate's Intent and Context. A
  script cannot grade it, so `scripts/link-suggest` only gathers candidates with that evidence,
  records a confirmed edge with a rating and reason, and flags drift.

**Branch vs root: the semantic decision.** The numbering is mechanics; choosing
*whether* to branch is meaning:

- **Branch (`14a`, `14b`):** a sub-task, refinement, or direct continuation of the
  parent. It cannot stand on its own; it only makes sense as part of the parent's work.
- **Root (`15`, `16`)**: an independent thought, even if inspired by another intent.
  Reserve `sources` for true created-from provenance (intents this was built out of). An
  independent intent merely related to or inspired by another carries NO `sources`; record
  the relation on the PREDECESSOR's `chain` (and mirror it as a
  `[[id--slug|<target's full intent: text>]]` wikilink in `## Links`).
- **Rule of thumb:** if the intent could exist without its parent, it's a root.
