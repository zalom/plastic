---
id: "1"
intent: "Build alpha from the founding design"
sources: ["global:51"]
chain: ["1a"]
created: 2026-09-17
author: human
tags: ["project-alpha", "service", "learning"]
---

## Intent
Build alpha from the founding design

## Context
Global intent 51 set the purpose, the layout and a phased plan for alpha. The
project repository now holds a guide, an architecture page, a roadmap and an
acceptance fixture. This intent carries the founding direction into the project.

### Decisions

- Keep the first release small, and grow it one measured step at a time.
- Run the first service on one shared server and reach it through a private
  connection.
- Keep the laptop side thin; run bounded workers on the server.
- Give every step explicit inputs, limits and acceptance evidence.
- Keep the guides shareable, and keep private records and secrets out of them.
- Build the service, the worker, the runtime and the recovery plan in separate
  intents.

## Outcome
(the result — implementation details, deliverables)

## Insights
(observations captured throughout — raw material for future intents)

## Links
- [[global:51--alpha-foundation|Found the alpha project from its design notes]]
- [[1a--beta-route|Deploy beta behind one stable address]]
