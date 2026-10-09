---
id: "1a"
intent: "Deploy beta behind one stable address"
sources: ["1"]
chain: []
created: 2026-09-17
author: human
tags: ["project-alpha", "beta", "network"]
---

## Intent
Deploy beta behind one stable address

## Context
The tested service answers only on the local machine. The next step is one stable
address for the laptop and for later workers. The shared server is the chosen host.
The address routes to the service through a private connection, with
authentication, logs, health checks and a clear answer when the route fails.
Other providers stay optional routes whose privacy and cost rules need separate
decisions.

This intent starts after the alpha guide and its first baseline. Its first work
is to inspect the server's network and capacity, then design and test the
smallest path. The tested service command stays fixed while the route is added.

## Outcome
(the result — implementation details, deliverables)

## Insights
(observations captured throughout — raw material for future intents)

## Links
- [[1--alpha-service|Build alpha from the founding design]]
