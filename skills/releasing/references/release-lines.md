# Release Lines and Channels

The two release lanes, the version-line map, and the intent-41 re-land playbook: the deep
material behind SKILL.md's "Release lines and channels" section.

## Table of Contents

- [The two lanes](#the-two-lanes)
- [Routing rule](#routing-rule)
- [Stable-line guarantees](#stable-line-guarantees)
- [Version-line map](#version-line-map)
- [Intent 41 re-land playbook](#intent-41-re-land-playbook)

## The two lanes

**Default lane.** Branch, merge to `main` with `--no-ff`, cut stable, publish to npm `latest`.
This is the workflow SKILL.md documents step by step. It is the path for additive,
suite-verifiable, low-blast-radius work: new skills, prose, deterministic scripts, anything a
green Minitest run can fully vouch for.

**Beta-verified lane.** Branch, merge to the `beta` branch, publish to the npm `beta` dist-tag,
verify in real use, then merge `beta` into `main` and cut stable. It sits on top of the existing
promotion mechanics (agent-performed channel promotion, linear only, see
`promotion-and-tagging.md`); it names when to use them, not new machinery.

## Routing rule

Work rides the beta-verified lane when it changes operational substrate, carries data,
migration, lock, or state-format risk, or cannot be fully validated by a hermetic suite alone.
Everything else merges straight to main.

Intent 41's DB layer is the archetypal beta-lane case: it replaces the bridge, lock, and session
file formats with a new persistent SQLite substrate. A green suite proves the code correct; it
cannot prove the new substrate survives real, uncontrolled usage, so real-use verification on
beta comes first.

The manual-first roadmap's eight 1.1.0 intents (158a, 163, 161, 164, 165, 168, 166, 159) are all
default-lane: skill directory renames, prose rewrites, deterministic step scripts. Additive, and
fully suite-verified.

## Stable-line guarantees

What an external `latest` user can rely on:

1. `main` is always green and releasable. No pending revert awaiting re-land sits on `main`.
   When something needs beta verification, it comes out of `main` the same day that need is
   found (the 226023f precedent), never left half-landed.
2. A stable release carries no pre-release suffix, publishes to npm `latest`, and the newest
   stable release always carries the GitHub "Latest" badge (`gh release create --latest` on
   every cut).
3. The three repo version files (`package.json`, `.claude-plugin/plugin.json`,
   `.claude-plugin/marketplace.json`) always agree. Checked mechanically by
   `scripts/lib/release_guard.rb`.
4. A stable cut collects only intents that cleared their lane's bar: default-lane intents by a
   green suite, beta-lane intents by suite green plus their lane's own verification (real-use
   signal, owner sign-off).
5. Channel semantics are fixed: `latest` is stable and what an external user should run; `beta`
   is the verification line, published but expected to move; `alpha` is experimental,
   pre-verification.

## Version-line map

| Line | State | What lands here |
|---|---|---|
| `1.1.x` | Current stable line (main) | Additive or low-risk work merged straight to main; interim stable cuts, including 171's wave-6 cut, stay in this line |
| `1.2.0-beta.1` | On beta (`9ec194b`, unpublished) | Intent 41's DB layer, restored over 1.1.0 by revert-of-revert (`c48601a` then `9ec194b`) |
| `1.2.0` | Reserved | The stable graduation of the DB layer, once beta verification passes; not claimed by any interim `1.1.x` cut |

A beta-graduated substrate change claims its reserved minor at the moment it actually merges to
main, not before. Nothing else on the `1.1.x` line is blocked waiting for `1.2.0`.

## Intent 41 re-land playbook

Written for the wave-6 cut intent (171) and any future reader to pick a version without
re-deriving this decision.

**Current state.** The revert-of-revert already sits on the `beta` branch at `9ec194b`, on top
of 1.1.0, versioned `1.2.0-beta.1` (`c48601a`). There is nothing left to execute on the git side;
this playbook describes what happens next, not a pending action.

**Preconditions**, both required before any npm publish of `1.2.0-beta.1`:

- (a) One documentation pass over beta-line skills and docs for the hybrid savepoint contract:
  on beta, only the terminal Done bookend still writes a live `savepoint.md`; every other
  milestone lives in `savepoint_events` plus a committed JSONL export. Beta-line prose that
  still assumes an always-live ledger needs updating first, so a beta-line reader does not
  mistake an empty ledger for a broken one.
- (b) The owner's manual verification of the DB layer in real use. This is a dogfood signal,
  distinct from the independently-reviewed green suite that already exists on beta.

**Trigger**, owner-gated: the owner publishes `1.2.0-beta.1` to the npm `beta` dist-tag. This is
explicitly not this intent's, nor any agent's, call to make.

**Verification.** An external tester plus the owner verify the DB layer on the beta channel.

**Completion.** Once verified, `beta` merges into `main`, `1.2.0` is cut stable, and it publishes
to npm `latest`.

**Version mechanics.** `1.2.0` is reserved for this graduation. The `1.1.x` line stays the
stable line until `1.2.0` actually lands. `1.2.0-beta.1` graduates to `1.2.0` stable by dropping
the pre-release suffix; nothing else about the version number changes.

**Consumed by 171.** The wave-6 consistency-dividend cut stays in the `1.1.x` line. It does not
ride intent 41 and needs no further derivation: intent 41 keeps its own `1.2.0` line on beta,
independent of whatever `1.1.x` number 171 lands on.
