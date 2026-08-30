# Locks and Worktrees

This chapter holds the delivery lock, claims, worktrees, the fail-safe doctrine, and the station-by-station delivery table. Since 2.0 (intent 302) nothing here blocks a write: the lock and the worktree are how an auto team keeps one delivery in one place, recorded by the record hook, not enforced by a hook.

### Delivery Isolation and the Single-Owner Lock

Locks and worktrees exist only for auto teams. An interactive session working direct or
thinking takes no lock: it records into the day ledger, or into the intent its per-session
pointer names (`~/.plastic/store/.tmp/<session>/current`, where `<session>` is the first eight
characters of the session id; the file holds today's day id or an intent id).

For an auto team, exactly one team develops an intent's delivery at a time. Ownership is
session-keyed and durable: arming acquires `delivery.lock` inside the intent directory
(atomically, O_EXCL). The session id is the authorization identity. Descriptive provenance
records the controller's explicit `harness`, `agent`, `model`, `thread`, and `mode` values,
but never grants access and is never inferred from transcripts or filesystem paths. Missing
fields on legacy locks display as `Unknown`. Liveness is a lease: the record hook refreshes
the lock file's mtime on every write the owning session makes, and that mtime is the sole
heartbeat truth. The lock counts as stale only when the mtime is older than the TTL. No
process id is consulted anywhere. The pointer file is a cache of which intent a session
records into; the lock file is the truth of who owns a delivery, and wins on any
disagreement. Another team that finds a fresh lock backs off; a stale lock is reclaimed only
by explicit takeover, which replaces the lock and appends an audit line to the intent's
savepoint.md. Rearming the same session preserves its acquired identity and refreshes known
provenance; an explicit takeover replaces the controller and starts new provenance.
Subagents spawned by the owner write under the owner's lock once registered as delegates.
Delegate activity status (`active`, `finished`, or `failed`) is descriptive and does not revoke
the session's string-array authorization. A registered delegate remains authorized until a
separate authorization-removal mechanism exists. Finished and failed delegate activity is
retained as descriptive history, bounded to the 20 most recent terminal entries. A controller,
a delegate, and an artifact claim are distinct evidence: controller ownership authorizes the
delivery, delegate registration authorizes a child session, and a claim selects one current
writer for one artifact. Disarm clears the lock; the End tail is ordered: verify, merge and
remove worktrees, clear the lock, and only then is the session pointer purge-eligible. Repair
is one idempotent function with two entry points: the `plastic-lock` command (`who`, status,
fix, release, reclaim, delegate) and the `plastic-doctor` skill's lock section, so repair
self-heals. `who` is read-only and reports the controller, mtime heartbeat, delegates, and
claims from durable files. This is mandatory for auto teams, not a convention.

The record hook resolves the current session in a fixed precedence: the stdin `session_id`
first, then the `CLAUDE_CODE_SESSION_ID` environment variable, then a derived key when neither
is present. A session's `.tmp/` directory is purge-eligible by terminal state, not by age: it
holds nothing durable, and losing it costs nothing. See [`docs/internals.md`](https://github.com/zalom/plastic/blob/main/docs/internals.md) for depth.

The delivery lock arbitrates at the whole-intent grain: it decides who may work an intent at
all. Underneath it, a per-artifact claim token (intent 111) is a coordination record at the
file grain: it names who, among those already holding the delivery lock, is the one writer for
one lifecycle file right now. Claims live in `.claims/<artifact>.claim` inside the intent
directory, one small JSON file per artifact, scoped strictly per-intent-per-artifact, never
session-global. Since 2.0 nothing enforces a claim at write time; a team lead takes and
releases claims through `plastic-lock claim` and `release-claim` to coordinate its executors,
and `plastic-lock status` lists any live claims alongside the delivery lock. A stale or corrupt
claim is reported there, never acted on. See [`docs/internals.md`](https://github.com/zalom/plastic/blob/main/docs/internals.md) for the full mechanism.

There is exactly one lock in Plastic: `delivery.lock` (exclusive, one owner plus delegates),
shipped by intent 108. An earlier two-lock doctrine proposed a second `maintenance.lock`
(short TTL, structural move-and-record only); intent 112 built it in full and was then
abandoned before merge on a design pivot, so nothing from it ever shipped (`lock.rb`'s
`TYPES` seam is the only trace left). Intent 197 rejects the second lock outright rather than
reviving it: a lock held by a maintenance session could be mistaken by a resuming session
for an active delivery. Maintenance instead DETECTS `delivery.lock`'s freshness
(`Lock.fresh?`) and defers when fresh; it never acquires any lock of its own and leaves none
behind. See "WORK vs MAINTENANCE" in `references/maintenance-and-revisions.md` for the full
doctrine.

Every code-touching auto intent gets its own git worktree named `{id}--{slug}`, and all code
edits for that intent happen inside it. Plastic provisions the worktree deterministically: it
resolves the project repo from `projects.yml` and runs `git -C <repo> worktree add`, so
isolation never depends on the current working directory. There is one worktree per project
intent, the code worktree at `<repo>/.claude/worktrees/{id}--{slug}` (branch
`plastic/{id}--{slug}`).

Plastic does not provision a second worktree for lifecycle-doc writes. Two things cover that
need instead. First, the harness's own native worktree: Claude Code manages its own code
worktree at `<repo>/.claude/worktrees/{name}`, and Codex manages its own at
`$CODEX_HOME/worktrees` (default `~/.codex/worktrees`); both exist on their own, independent of
anything Plastic provisions. Second, intent 197's branch-from-main plus scoped commit, which
gives store writes their own write safety without a dedicated worktree. Plastic tried a second,
dedicated store worktree at `<plastic_home>/.worktrees/{id}--{slug}` first; agents never wrote
into it, because every delivering agent writes lifecycle docs straight to the main store
checkout, so intent 178 retired the store worktree in favor of the two mechanisms above.

Provisioning fails open for intents that touch no project code (pure research or decision
intents in the global store, or a non-git repo): those get the lock only, and the worktree
block stays unprovisioned. The fail-open path is always logged, never silent.

Cleanup is part of Done: the End tail merges the branch, then removes the worktree. Never leave
an orphaned worktree behind, and clear a stale worktree reference with `git worktree prune`.


#### Intent delivery, station by station

How one auto-team intent travels from boarding to Done, and what the lock, the pointer, and
the record hook do at each station. Nothing in the third column blocks; the fourth column is
what gets written down.

| Station | Delivered artifact | Lock and pointer steps | Record |
|---|---|---|---|
| Start (board) | none (a procedure, not a stage) | `plastic-lock fix` self-heals stale, corrupt, or legacy state; arm acquires `delivery.lock` (O_EXCL, session-keyed), provisions the code worktree, writes the session pointer | savepoint confirms the boarding station |
| What (create) | `<id>--<slug>.md`, born complete | no lock yet; `new-intent` validates the file it writes (`scripts/validate-intent`) | savepoint `What` line; intent listed in INDEX `## Active` |
| Why | `spec.md` | owner writes refresh the lease (lock file mtime heartbeat) | savepoint `Why started`, `Why spec.md created` |
| How | `plan.md`, `actions/ACTION_N.md` (at least one), `checklist.md` | heartbeat on writes | savepoint `How started`, `How plan.md created`, `How checklist.md created`, `Exec started` |
| Exec | code on the intent branch, checklist checked off | heartbeat; code edits confined to the provisioned worktree; delegates write under the owner's lock | checklist boxes; savepoint milestones; the day-ledger line promotes when a project file lands |
| End (done) | mandatory `outcome.md` (`disposition: delivered\|abandoned`), INDEX moves to Completed or Abandoned | ordered End tail: verify, merge and remove worktrees, disarm clears `delivery.lock`, then the pointer is purge-eligible, and the QMD reindex runs LAST (after purge); `end-intent`'s structure check refuses a placeholder `outcome.md` | savepoint `Done delivered` (or `abandoned`); takeover audits, if any, remain in savepoint.md |
| Maintenance (Future, Terminal, or Active-with-a-stale-or-no-lock) | `revisions.md` move-and-record entries | detects (never acquires) `delivery.lock`; defers and reports while the target's lock is FRESH (`Lock.fresh?`); a stale or absent lock is not-active, maintenance proceeds | append-only, rule-tagged `revisions.md` entry written in the same operation as the change, or the change is refused; lands via a fresh branch off store main merged back as one closed op, never `git add -A` |
