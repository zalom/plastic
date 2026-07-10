# Roadmap: Frontier wave 4 fixture

Trimmed copy of the live `consistency-dividend.md` shape (intent 148), waves 1-3 delivered,
wave 4 two `delivering` entries (one with a trailing parenthetical), wave 5 one `queued`. Proves
the robust status parser against the real trailing-parenthetical shape, and the headline
in_flight assertion: wave 5's entry must never surface as dispatchable while wave 4 is live.

## Goal

Fixture only, not the live roadmap; copied in shape and voice.

## Waves
Entries in a wave are parallel-safe; waves run top to bottom. The checkbox tracks
delivered/not; the token after the dash carries the precise mirrored status (queued |
delivering | delivered | abandoned | blocked); INDEX wins on any conflict.

### Wave 1
- [x] 169 Unify the hermetic home seam — delivered
- [x] 136 Fix-path arm provisions a complete bridge — delivered

### Wave 2
- [x] 133 Keep the empty actions dir across a fresh checkout — delivered
- [x] 158a1 Continuing front-door router — delivered

### Wave 3
- [x] 149 Dashboard becomes prose summaries — delivered
- [x] 134 Roadmap savepoint ledger — delivered

### Wave 4
- [ ] 148 Roadmaps become the primary feature — delivering
- [ ] 133a Actions mandatory at every tier — delivering (owner ruling; carved from the 133 follow-up)

### Wave 5
- [ ] 85b Skill-lint runner — queued

## Log
- 2026-07-10 02:20 UTC Roadmap created on the owner's selection.
- 2026-07-10 13:42 UTC Wave 4 opened: 148 and 133a activated and dispatched.
