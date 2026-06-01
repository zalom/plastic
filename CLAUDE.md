# Plastic — Claude Code Instructions

All Plastic conventions are defined in `~/.plastic/AGENTS.md`. Read and follow it.

This file is for Claude Code-specific rules and project decisions only.

## Decisions Log

| # | Decision | Choice | Date | Reason |
|---|----------|--------|------|--------|
| D1 | Testing framework | Minitest | 2026-05-22 | 37signals methodology |
| D2 | Code navigation | Serena MCP primary | 2026-05-22 | Symbolic tools over grep |
| D3 | Project name | Plastic | 2026-05-24 | Neuroplasticity metaphor |
| D4 | State system | Intent-driven, Zettelkasten linking | 2026-05-24 | File-based, git-native, extractable |
| D5 | All skills through intents | Intents are the foundation | 2026-05-24 | Single coherent system |
| D6 | Researches are intents | Intents, no special type | 2026-05-24 | No separate folder needed |
| D7 | Directory hashing | SHA-256 → base36, 6 chars | 2026-05-24 | Deterministic, no gems, collision-safe |
| D8 | Vector database | SQLite + sqlite-vec via neighbor gem | 2026-05-24 | Ruby-native, no external services, migration path to pgvector |
| D9 | Stale intent threshold | 3 days | 2026-05-24 | Balance between actionable nudging and not being annoying |
| D10 | Defer-to-agent modes | implement / research / ideate | 2026-05-24 | Covers the full spectrum from execution to exploration |
| D11 | Plugin distribution | GitHub repo as self-hosted marketplace | 2026-05-24 | Same pattern as Continuum (zalom/continuum) |
| D12 | Global intent store | ~/.plastic/ as git-backed repo | 2026-05-25 | Agent-agnostic, intents spawn projects |
| D13 | Two-tier architecture | Strategic (global) + tactical (project) | 2026-05-25 | Avoid cluttering global store with sub-tasks |
| D14 | Wikilink format | [[NNN-HASH]] with global:/project: prefixes | 2026-05-25 | Grep-friendly, Zettelkasten-native, resolver-friendly |
| D15 | Frontmatter | Identity only, links in body as wikilinks | 2026-05-25 | Single file = single source of truth, no drift |
| D16 | Convention-over-configuration | Filesystem as schema | 2026-06-01 | Presence of sections/files signals state, not explicit fields |
| D17 | What→Why→How→Next lifecycle | Sections replace status field | 2026-06-01 | Intent/Context/Insights/Outcome map to lifecycle phases |
| D18 | Minimal frontmatter | id, intent, sources, chain, created, author, tags | 2026-06-01 | Remove status, type, project, parent — derive from conventions |
| D19 | AGENTS.md as contract | Conventions codex for all agents | 2026-06-01 | Single source of truth for agent behavior rules |
| D20 | Projects as hubs | Two-store architecture, project-\<name\> tags | 2026-06-01 | Strategic intents link to projects via tags and chain |
