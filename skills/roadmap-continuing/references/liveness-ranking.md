# Liveness Ranking (read time, no new field)

Depth reference for "Find the mid-flight roadmap" in `SKILL.md`. This is the full algorithm the
body summarizes.

## Why read-time, not a stored field

INDEX.md stays the sole writer of intent status; the roadmap file mirrors it (see
`plastic-roadmap`'s `references/file-format.md`). Adding a "mid-flight" flag to the roadmap
file or to INDEX.md would create a second thing to keep in sync for a question that is cheap to
answer by reading what is already there. So liveness is computed fresh, every time this skill
runs, from the tier's live `roadmaps/*.md` files (excluding `roadmaps/archived/`).

## The algorithm

1. **Enumerate.** List every `roadmaps/*.md` at the tier (project or global), skipping
   `roadmaps/archived/`.
2. **Delivering/blocked wins outright.** If any candidate roadmap has at least one `## Waves`
   entry whose mirrored status token is `delivering` or `blocked`, it is in flight right now.
   That candidate wins the ranking immediately; skip the rest of the ranking for it.
3. **Otherwise, newest `## Log` entry wins.** Among the remaining candidates (none have a
   `delivering`/`blocked` entry), read each file's last `## Log` line (append-only, newest at
   the bottom) and rank by that line's `YYYY-MM-DD HH:MM UTC` timestamp. The most recent wins.
4. **Genuine tie -> present, do not silently pick.** If two or more candidates are equally live
   (for example two roadmaps both idle with `## Log` entries on the same timestamp, or two both
   showing `delivering` entries with no other signal to separate them), do not choose for the
   user. Present both/all tied candidates' state side by side, then let the single "auto or
   guided?" ask (asked once regardless of how many candidates were presented) double as the
   resolution: the user's answer implicitly picks by naming which roadmap to continue, or the
   agent asks a short one-line disambiguation immediately before that same single ask, never a
   second separate prompt.

## What this closes

Before this skill existed, nothing resumed a mid-flight roadmap automatically. The `171`
(consistency-dividend) roadmap handoff had to be resumed by hand: a free-prose "SESSION
HANDOFF" note written into `171`'s own `## Insights`, because no skill read `## Waves` +
`## Log` and reconstructed where the batch stood. This ranking is the mechanism that replaces
that hand-carried note.

## Grammar pointer (do not duplicate)

The roadmap file's four sections, entry line shape, and status vocabulary
(`queued|delivering|delivered|abandoned|blocked`) are owned by `plastic-roadmap`:
`skills/roadmap/references/file-format.md` for the shape, and
`skills/roadmap/references/operations.md#read--consume` for how a reader (human or
coordinator) is meant to walk `## Waves` and `## Log`. This page assumes that grammar and adds
only the liveness-ranking judgment on top of it.
