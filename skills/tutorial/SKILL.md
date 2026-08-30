---
name: plastic-tutorial
description: >-
  Teach a new user how Plastic works through one of three hands-on tracks: deliver a first
  intent stage by stage, hand delivery to the agent in auto mode, or grow a founding intent
  into a small project with a roadmap. Use when the user says "tutorial", "teach me Plastic",
  "walk me through Plastic", "how do I use Plastic", or asks what Plastic can actually do
  before trying it on real work.
user-invocable: true
---

# Plastic Tutorial

An interactive coach, not an automator. It walks one of three tracks, one step at a time, and
keeps no state of its own: the intent being used for the walkthrough is the progress bar.

## The three tracks

This is the one menu in the whole skill. Offer it, then route into the picked track's
reference. Every checkpoint inside a track is prose, never another menu.

1. **Guided**: deliver a first intent, stage by stage, approving each step yourself. Routes to
   `references/track-1-guided.md`.
2. **Auto**: hand delivery to the agent and watch the record and reports as it works. Routes to
   `references/track-2-auto.md`.
3. **Projects and roadmaps**: grow a founding intent into a small real project, add more
   intents, and plan a delivery batch with a roadmap. Routes to
   `references/track-3-projects-and-roadmaps.md`.

If the user names what they want instead of picking a number ("show me auto mode", "I want a
roadmap", "walk me through my first intent"), route straight to the matching track without
showing the menu again.

## The coach contract

Narrate one step at a time: say what the next station does, then hand control back so the
user types the real command themselves. After they run it, look at what appeared (a file, a
ledger line, a report) and debrief in plain words before moving to the next station. Never
run a station's command on the user's behalf; the tutorial teaches the shape of the work, it
does not do the work.

Keep no new state. The intent's own lifecycle stage and savepoint are the only progress
record. This skill never writes a "tutorial progress" file of its own.

## The resume rule

To pause, the user says "continue the tutorial." Read the walkthrough intent's current stage
and savepoint (for track 3, check which project-scaffolding steps are already on disk) and
resume at the matching station. Do not restart from station one, and do not ask the user to
remember where they left off.

## Routing table

| Trigger | Reference |
|---|---|
| User picks "guided", or names their first intent, a first delivery, or learning the stages one at a time | `references/track-1-guided.md` |
| User picks "auto", or says "hand it to the agent", "run the whole thing", "show me auto mode" | `references/track-2-auto.md` |
| User picks "projects and roadmaps", or says "start a project", "I want a roadmap", "plan a batch of work" | `references/track-3-projects-and-roadmaps.md` |

## Before any track

Every track opens with the same two checks: run `/plastic-update` first (`$plastic-update` on
Codex), so the walkthrough matches what is actually installed, and work in a sandbox (a
throwaway repo, or a global-store intent) so nothing real is touched by mistake. Each reference
restates this briefly; do not skip it even if the user seems experienced.
