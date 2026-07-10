# Roadmap: Consistency dividend

Fixture excerpt of the real `roadmaps/consistency-dividend.md` (intent 171), trimmed to a small,
hand-verifiable `## Waves` plus `## Log` pair for `test/roadmap_savepoint_test.rb`'s rebuild
assertion. Not the live roadmap; copied in shape and voice only.

## Goal

The lint runner enforces conventions the manual-first audit checked by hand; all entries below
are delivered and a stable release is cut.

## Waves
Entries in a wave are parallel-safe; waves run top to bottom. The checkbox tracks
delivered/not; the token after the dash carries the precise mirrored status (queued |
delivering | delivered | abandoned | blocked); INDEX wins on any conflict.

### Wave 1
- [x] 101 Alpha fix — delivered
- [x] 102 Beta fix — delivered
- [x] 103 Gamma fix — delivered

### Wave 2
- [ ] 104 Delta feature — delivering

## Log
- 2026-07-10 02:20 UTC Roadmap created on the owner's selection.
- 2026-07-10 02:58 UTC Added 104 to wave 2.
- 2026-07-10 03:00 UTC 101 delivered: alpha fix shipped, see store/101--alpha/outcome.md.
- 2026-07-10 03:10 UTC Wave 2 activated: 104 dispatched.
- 2026-07-10 03:20 UTC ACCOUNT SESSION LIMIT hit: team working on 105 parked mid-wrap.
