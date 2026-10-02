# Changelog

Release history for Plastic, one line per cut. Commit-level detail lives in
[GitHub Releases](https://github.com/zalom/plastic/releases).

## Unreleased

- Archive captures complete intent directories before deletion and restores them through `intent archive ID --revert`. `sync up` imports legacy rulings, links, roadmaps, and preserved originals; `--dry-run` previews the same operation in a copy. The separate migration command is removed.

- Stage 5 acceptance documents cover every added command. The test helpers decode multiline specs and isolate Codex session identifiers. CI also runs on pull requests targeting stacked `plastic/` branches.
- `roadmap drop` names a missing roadmap or item before attempting a write. A migration dry run labels its totals as proposed imports and offers the apply command.

- Delivered intents close through `intent end` with explicit criterion evidence and a judge. Closure records the outcome hash, releases the delivery lock, and can be retried without duplicating acceptance. Empty and completed graph handoffs now lead to planning or verification. Node completion requires findings; `--repair` records verification for an existing done node. Sync no longer imports graph.json.
