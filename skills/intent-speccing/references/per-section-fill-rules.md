# Per-Section Fill Rules

The single shared method for turning the rulings into `spec.md`. `plastic-intent-speccing`
(the thinking conversation) and the auto orchestrator both point here; neither restates these
rules. One fill rule per template section, in template order.

Read the ruling ledger first (built in step 2 of the SKILL.md sequence): `## Context` plus
`### Decisions`, then `## Insights` newest-last (a later ruling supersedes an earlier
conflicting one), then `resources/discovery--<slug>.md`, then any other `resources/*.md`.
Every rule below names which part of that ledger feeds the section.

## 1. Problem

Source: the intent's `## Intent` line plus the problem narrative in `## Context`.

State the problem as a problem, not a solution: what is broken, missing, or costly today, for
whom. Do not describe the fix here, that belongs in Approach. If `## Insights` records a later
reframe of the problem (a scope correction, a retargeted root cause), the later framing wins.

## 2. Goals

Source: explicit goal statements in `## Context`, plus any `### Decisions` entry that commits to
delivering a specific outcome.

One bullet per goal, each a concrete, observable outcome the delivery must reach. Encode every
Decision that commits to an outcome as its own bullet, do not compress two Decisions into one
vague goal. A single-line collapsed Goals section is complete if it names every
outcome; do not pad it with restated Problem text.

## 3. Non-Goals

Source: `### Decisions` entries that name something explicitly out of scope, and `## Insights`
rulings that narrowed scope after the initial brainstorm.

One bullet per excluded item, each naming what is out and, briefly, why (a sibling intent owns
it, a scope-reframe ruling cut it, it is a future intent). If a later Insight narrows scope
further than an earlier Decision, the Insight's narrower boundary is the one recorded.

## 4. Approach

Source: every `### Decisions` entry that describes HOW, resolved into one coherent narrative.

Write prose, not a decision list. Synthesize the chosen path so it reads as one design: what
gets built, in what shape, and how the pieces fit. Every Decision that shapes the approach must
be traceable to a sentence here, but do not restate each Decision by its Dn label, that
enumeration belongs in the Decisions section. Use a table only where the Approach itself compares
options inline (rare; usually that comparison belongs in Alternatives Considered instead).

## 5. Alternatives Considered

Source: `### Decisions` entries and `## Insights` rulings that name a rejected path and the
reason it lost.

Render as a table, not the template's bullet-dash form, so the reason column stays uniform and
free of dash-glyph punctuation:

| Alternative | Not chosen because |
|---|---|
| <rejected path> | <the ruling's stated reason, paraphrased> |

One row per rejected alternative. If two Decisions reject variants of the same alternative, merge
them into one row rather than duplicating it. Never use an em-dash or en-dash in the reason
column; write "because" or a colon instead.

## 6. Decisions

Source: `### Decisions` verbatim, in the order recorded, one entry per Decision.

One bullet per decision, each keeping its `Dn` label and its ruling in paraphrase or verbatim.
Do not drop a decision because it seems minor: every Decision must appear here even if its effect
on the shipped Approach or Goals is small. When `## Insights` records a later ruling that
supersedes an earlier Decision, add or amend the bullet to state the later ruling and note which
earlier Decision it supersedes.

## 7. Acceptance Criteria

Source: any criteria named directly in `### Decisions` or `## Insights`, plus one inferred
criterion per Goal that has no explicit criterion on record.

One checkbox bullet per criterion, each concretely checkable: a fact a reviewer can confirm true
or false by inspection, a command, or a file, never a vague quality judgment. Every Goal must map
to at least one criterion. A criterion that cannot be checked without more interpretation is not
done, rewrite it or ask (the gap rule, SKILL.md step 5).

## 8. Open Questions

Source: any question raised during Why that has no matching Decision or Insight resolving it.

List each unresolved question as its own bullet. If every question raised during Why has a
resolving Decision or Insight, write `None` and, directly under it, one line per resolved
question naming which Decision or Insight resolved it (so a reader can audit the resolution
instead of taking "None" on faith).
