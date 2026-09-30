---
id: "1"
intent: "Build ai-infra from the founding design"
sources: ["global:51"]
chain: ["1a"]
created: 2026-09-17
author: human
tags: ["project-ai-infra", "infrastructure", "learning"]
---

## Intent
Build ai-infra from the founding design

## Context
Global intent 51 established the purpose, topology, phased learning plan, and first
measured vLLM baseline. The project repository now holds a publishable cross-platform
guide, the architecture guide, the roadmap, and a Rails acceptance fixture. This
tactical mirror carries the founding direction into project implementation.

### Decisions

- Keep local models as a first-class execution tier, with measured expansion to
  multiple models and GPUs.
- Run the first LiteLLM gateway on the Dell T430 Proxmox server and route to the
  current Windows/WSL2 inference node through a controlled private connection.
- Keep MacBook orchestration thin; run bounded workers and future project
  environments on the server.
- Give graph nodes explicit context, tools, limits, and acceptance evidence.
- Keep guides and learning resources shareable. Separate tested instructions from
  documentation-based paths and do not publish private Plastic records or secrets.
- Implement the gateway, local worker, graph runtime, model evaluation, LoRA,
  project platform, server GPU migration, and cloud recovery in separate intents.

## Outcome
(the result — implementation details, deliverables)

## Insights
(observations captured throughout — raw material for future intents)

## Links
- [[global:51--local-ai-infrastructure-foundation|Define and found a local AI infrastructure project using the supplied multi-agent guides as design inputs]]
- [[1a--litellm-proxmox-gateway|Deploy a LiteLLM gateway on Proxmox with a stable local model alias]]
