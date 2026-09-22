# Plan: Reporting improvements V2

The speed question first: what speeds up per-intent delivery now? One grammar registry in
ScreenPaint (331a) so each later screen adds an opener and a paint rule in one place, one shared
replay harness as a test fixture, and orchestrator-written How artifacts for every branch intent
(they are designed here; no Why agents). Each branch intent then runs as one background enforcer
lead with one executor and one reviewer, parallel within a batch.

## Steps

- S1 Evidence and record: catalog artifact, replay harness, transcript census, live PTY probes,
  evidence file, spec D1-D12, Context with the family and its sources and chain edges.
- S2 Roadmap `reporting-v2` with four batches and the seven branch intents 331a-331g in the
  INDEX; each branch intent carries its own How written by the orchestrator before dispatch.
- S3 Batch 1: 331a delivered on alpha (hook engages anywhere, grammar registry).
- S4 Batch 2: 331b, 331c, 331d delivered on alpha in parallel.
- S5 Batch 3: 331e, 331f delivered on alpha in parallel.
- S6 Batch 4: 331g delivered: captures for every screen, owner's agents-view check, alpha cut.
- S7 Close: outcome.md with the Delivered table, evidence file updated with every new capture,
  catalog artifact republished, roadmap archived.

## Risks

- ScreenPaint is shared by every batch-2 intent: the registry from 331a must land first, and
  each batch-2 branch adds its own file under `scripts/lib/screens/` rather than editing the
  registry body, so merges stay clean.
- The agents view is not machine-testable; the owner's one look is the acceptance for it.
