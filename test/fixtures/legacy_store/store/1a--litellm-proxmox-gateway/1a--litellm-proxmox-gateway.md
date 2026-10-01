---
id: "1a"
intent: "Deploy a LiteLLM gateway on Proxmox with a stable local model alias"
sources: ["1"]
chain: []
created: 2026-09-17
author: human
tags: ["project-ai-infra", "litellm", "proxmox"]
---

## Intent
Deploy a LiteLLM gateway on Proxmox with a stable local model alias

## Context
The tested laptop vLLM service is available only on WSL loopback. The next platform
capability is one stable gateway URL for the MacBook and later graph workers. The
Dell T430 Proxmox server is the chosen host for persistent routing. The gateway
will route a stable local model alias to laptop inference through a controlled
private connection, with authentication, logs, health checks, and explicit
behavior when the route fails. NVIDIA NIM and other providers remain optional
routes whose privacy and cost rules need separate decisions.

This intent starts after the publishable vLLM guide and phase-one baseline.
Its first work is to inspect the actual Proxmox networking and VM capacity,
then design and test the smallest gateway path. The measured laptop serve
command remains pinned while routing is introduced.

## Outcome
(the result — implementation details, deliverables)

## Insights
(observations captured throughout — raw material for future intents)

## Links
- [[1--ai-infra|Build ai-infra from the founding design]]
