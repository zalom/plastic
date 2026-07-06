# Roadmap: <name>

(one-line meta: what this roadmap delivers, and which store it lives in)

## Goal
(a checkable prose condition — one or a few sentences a human or coordinator reads to decide the
roadmap is done. Not an executable checker.)

## Waves
Entries in a wave are parallel-safe; waves run top to bottom. Each entry mirrors INDEX status
(queued | delivering | delivered | abandoned | blocked); INDEX wins on any conflict.

### Wave 1
- <intent-id> <title> — queued
- <intent-id> <title> — queued

### Wave 2
- <intent-id> <title> — queued

## Log
(append-only, dated, one line per event: created / entry added / wave completed / status changed /
roadmap closed. Newest at the bottom.)
- 2026-01-01 created
