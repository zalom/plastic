# Plastic - Reference

> **This file is maintained by Plastic.** It will be overwritten when the
> plugin is updated. It holds reference material: read it on demand, it is
> not injected at session start.

### Structural maintenance and revisions.md

When a delivered intent accumulates structural junk (an unsanctioned section, a stray file, a
frontmatter edge to an intent that no longer exists), the intent-curator relocates it into
`revisions.md` instead of reopening the work. Each entry is a versioned, dated header
(`## Revision vN - YYYY-MM-DD-HH:MM`) plus `Why` (one sentence naming the broken rule, ending
with `[rule: <tag>]`), `Prior location`, and either `Content held` (the verbatim removed
content) or, for a frontmatter edit, a one-line `Change` (before and after). A stray file has
its full content embedded and the original is deleted.

Violation tags (starter set, free-text tags allowed):
- `unsanctioned-section`: a top-level section the sanctioned-section rule now rejects
- `phantom-section`: a section referenced but not present or not sanctioned
- `stray-file`: a file that does not belong in the intent directory
- `dangling-ref`: a link or reference to something that no longer exists
- `broken-chain`: a chain frontmatter edge to an intent that no longer exists
- `broken-source`: a sources frontmatter edge to an intent that no longer exists
- `misplaced-content`: content that belongs in a different artifact or section

## Two Processes

| Process | Scope | Type | Actor |
|---|---|---|---|
| **Build → Observe → Repeat** | The system | Continuous loop | Coordinator |
| **What → Why → How → Exec** | One intent | Finite lifecycle | Agent |

B→O→R is the Coordinator's heartbeat. W→W→H→E is what happens inside each intent.
The connection: an intent's `## Insights` feeds the Coordinator's Observe phase.

## Defaults-First

Plastic stands on its own. Skills and agents use Plastic's own defaults; an
external skill (for example `superpowers:*`) is opt-in, never load-bearing.

- **Default to Plastic, delegate by exception.** Name the Plastic-native path as
  the default. Delegate to an external skill only when (a) it is available in the
  harness, or (b) the user explicitly asks for it. A user without that plugin must
  still get the core behavior.
- **Phrase external skills as enhancements.** Write "use Plastic's native X by
  default; if `superpowers:<skill>` is available, or the user prefers it, delegate
  to it" never "delegate to `superpowers:<skill>`" as the only path.
- **Optional dependencies detect then degrade.** `qmd` is the reference shape:
  `scripts/lib/qmd_sync.rb` detects the binary first and every verb no-ops cleanly
  when it is absent (see `scripts/qmd-sync`). Optional CLIs and MCP servers follow
  the same detect-then-skip pattern, so a missing tool never crashes a session.
- **Legitimate hard dependencies are exempt.** Ruby, Node, git, and POSIX tools are
  the cost of running Plastic, not silent coupling. The principle targets accidental
  dependence on external skills doing work Plastic should do itself.

## Roadmaps

Roadmaps exist for planned parallel delivery of intents in a coherent and organized way. A roadmap
is a named, ordered, delivery-side collection of intents: the delivery-side counterpart to a
release (completion-side, tracked in `CHANGELOG.md`). Use `plastic-roadmap` to create, order,
close, and consume one.

File location: `roadmaps/{slug}.md`, a sibling of `INDEX.md`, wherever `INDEX.md` lives, never
inside `store/` (store holds intent directories, not project artifacts). For a project that is its
root, `~/.plastic/projects/{slug}/roadmaps/`, beside `project.yml`; for the global tier it is
`~/.plastic/roadmaps/`, beside `~/.plastic/INDEX.md`. `roadmaps/` lists only live (open or
in-flight) roadmaps: once a roadmap's goal is reached, it moves to `roadmaps/archived/{slug}.md`,
a sibling subdirectory scaffolded once with a `.gitkeep`.

A roadmap file has four sections, in order: a title/meta header, `## Goal`, `## Waves`, and an
append-only dated `## Log`. `## Goal` is a checkable prose condition read by a human or agent, not
an executable checker. `## Waves` holds ordered waves; entries inside a wave are parallel-safe,
waves run sequentially, top to bottom.

Each wave entry carries a status token (`queued`/`delivering`/`delivered`/`abandoned`/`blocked`)
that mirrors that intent's status in `INDEX.md`. `INDEX.md` is the single writer of intent status;
on any conflict INDEX wins and the roadmap entry is corrected to match.

**Human-comprehension surface.** A roadmap is also written to be read cold. Wave entries render as
checkboxes (checked once delivered, unchecked otherwise) next to the status token, and each `## Log`
line is one plain-language sentence, starting `YYYY-MM-DD HH:MM UTC`, written the way an
engineering manager would brief a non-expert executive: what shipped and why it matters, no jargon
or codenames, ending with a link
to that intent's `outcome.md`. The log points at the detail instead of repeating it, so a person
opening the file with no other context can tell what shipped, what is running now, and what is
next in under a minute.

**Relationship to loop engineering (intent 69).** A roadmap is the planning half of the work; the
loop is its runtime. Waves lay out the parallelism plan: what can run together, and in what order.
Loop engineering (intent 69, not yet delivered) is expected to consume that plan and supply the
running parts, the heartbeat, how many dispatches run at once, checking the goal, and resuming
after a stop. This section only states the relationship and points to intent 69 as the future
consumer; it does not change intent 69's own design.

## Context-economy measurement buckets (84a)

Intent 84 defines three buckets for sibling 84a to audit against; 84 does not run the audit.

- (a) gate-hook prose tokens: the per-transition narration emitted by the gate hook.
- (b) main-loop store-read tokens: tokens the main agent spends reading or grepping the store
  in the transcript.
- (c) authored-section sizes: sizes of authored artifacts (INDEX entries and the like).

## Deprecation Process

Deprecations live in `deprecations.yml` and are shown at SessionStart. While Plastic is
pre-1.0, a satisfied deprecation (its migration is already done on installed machines) may be
removed immediately instead of waiting for its declared `removal` version. From `1.0.0` on,
the steady-state grace rule applies (removal at least two minors ahead). For the full process,
severity levels, and the pre-1.0 exception, see the `plastic-releasing` skill.

## Skills Reference

Detailed conventions live inside the skills that use them, not in this file.

| Topic | Skill | References in skill |
|-------|-------|-------------------|
| Creating intents, lifecycle | `plastic-creating-intent` | lifecycle, wikilinks |
| Brainstorming, spec writing | `plastic-brainstorming` | — |
| Planning, actions | `plastic-writing-plans` | — |
| Execution, delivery | `plastic-executing-plan` | — |
| Autonomous delivery | `plastic-auto` | agent architecture |
| Save/restore state | `plastic-savepoint`, `plastic-continuing` | context management |
| Knowledge graph, linking | `plastic-linking-intents` | zettelkasten, wikilinks |
| Projects, hubs | `plastic-creating-project` | hubs, project stores |
| Provision a project store | `plastic-add-project-store` | project stores |
| Index maintenance | `plastic-managing-index` | — |
| Releases, deprecations | `plastic-releasing` | deprecation process |
| Health diagnostics | `plastic-doctor` | three scopes: `--core` (binary install-integrity check, runs on SessionStart), `--store [global\|<slug>]` (per-store check, runs on dashboard load), no flag = full check (runs after every update); gate enforcement, stuck detection |
| Authoring skills, agents, hooks | `plastic-creating-skills` | progressive disclosure, agentskills.io spec |
| Evaluating skills, evals | `plastic-evaluating-skills` | eval methodology, convention checks |
| Create, order, and consume a roadmap of intents | `plastic-roadmap` | file format, operations |

