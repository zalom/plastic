---
name: plastic-continuing
description: >-
  Use when the user says "continue", "resume", or "pick up where we left off", starts a new
  session and wants to keep going, asks "what should I work on", or asks a where-was-I question
  that never says "continue" (for example "where was I"). This is the front door for resuming
  work: it dispatches to plastic-intent-continuing (a specific intent named to resume),
  plastic-project-continuing (the default, general board landing), or
  plastic-roadmap-continuing (a roadmap or delivery batch named to resume).
user-invocable: true
---

# Continuing - the front door

`plastic-continuing` is the front door for resuming work (ruling 96: continuing routes,
starting does the lock plus resume plus work). It routes to exactly one of three skills and
does nothing else: no ledger-resume, no dashboard render, no roadmap read happens here.

## Route

| Args / context | Route to |
|---|---|
| `--intent {id}`, or the user names one specific intent (by id or description) to resume | `plastic-intent-continuing` (intent route) |
| `--roadmap {slug}`, or the user asks to continue/resume a roadmap or delivery batch | `plastic-roadmap-continuing` (roadmap route) |
| bare "continue" / "resume" / no further target (default) | `plastic-project-continuing` (project route) |

## Announce, then hand off

State the chosen route in one line before delegating (this is the router's own "present state
before any ask" - the router asks nothing itself). Example: "Routing to the project board (no
specific intent or roadmap named)."

Then hand off to the chosen skill. Do not inline any of the routed skill's own work here -
that belongs to the routes.
