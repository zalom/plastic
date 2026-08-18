# Locks and Worktrees

This chapter holds the delivery lock, claims, worktrees, solo mode, fail-safe doctrine, and the station-by-station delivery table.

### Delivery Isolation and the Single-Owner Lock

Exactly one session or agent develops an intent's delivery at a time. Ownership is
session-keyed and durable: arming acquires `delivery.lock` inside the intent directory
(atomically, O_EXCL). The session id is the authorization identity. Descriptive provenance
records the controller's explicit `harness`, `agent`, `model`, `thread`, and `mode` values,
but never grants access and is never inferred from transcripts or filesystem paths. Missing
fields on legacy locks display as `Unknown`. Liveness is a lease: the owner's hooks refresh
the lock file's mtime on tool activity, and that mtime is the sole heartbeat truth. The lock
counts as stale only when the mtime is older than the TTL. No process id is consulted anywhere.
The /tmp session bridge is a cache
of this state; on any disagreement, or when the bridge is missing, the lock file wins.
Another session that finds a fresh lock backs off; a stale lock is reclaimed only by
explicit takeover, which replaces the lock and appends an audit line to the intent's
savepoint.md. Rearming the same session preserves its acquired identity and refreshes known
provenance; an explicit takeover replaces the controller and starts new provenance.
Subagents spawned by the owner write under the owner's lock once registered as delegates.
Delegate activity status (`active`, `finished`, or `failed`) is descriptive and does not revoke
the session's string-array authorization. A registered delegate remains authorized until a
separate authorization-removal mechanism exists. Finished and failed delegate activity is
retained as descriptive history, bounded to the 20 most recent terminal entries. A controller,
a delegate, and an artifact claim are distinct evidence: controller ownership authorizes the
delivery, delegate registration authorizes a child session, and a claim selects one current
writer for one artifact. Disarm clears the lock; the End tail is ordered: verify, merge and remove
worktrees, clear the lock, and only then is the bridge purge-eligible. Repair is one
idempotent function with two entry points: the `plastic-lock` command (`who`, status, fix,
release, reclaim, delegate) and `/plastic-intent-starting`, so boarding self-heals. `who` is
read-only and reports the controller, mtime heartbeat, delegates, and claims from durable files.
This is
mandatory, not a convention.

Solo-mode gate defaults (intent 128): on a confirmed positive solo determination
(`Bridge.solo_delivery?`, a single owner working alone with no sign of parallel or team
delivery), the lock and worktree arbitration gates relax from enforced to advisory. The moment
any parallel or team activity appears they return to strictly enforced. This is a real behavior
difference, not just a message change: a solo session is not hard-blocked by these gates, a
shared one still is.

The bridge resolves the current session in a fixed precedence: the stdin `session_id` first, then
the `CLAUDE_CODE_SESSION_ID` environment variable, then a derived key when neither is present. A
bridge is purge-eligible by terminal state, not by age: it is removed only once its intent is no
longer active, never on a timer. See `docs/internals.md` for depth.

The delivery lock arbitrates at the whole-intent grain: it decides who may work
an intent at all. Underneath it, a per-artifact claim token (intent 111)
arbitrates at the file grain: it decides who, among those already holding the
delivery lock, is the one writer for one lifecycle file right now. A write to
`spec.md`, `plan.md`, `checklist.md`, or the intent file must hold both the
delivery lock and that file's claim. Claims live in `.claims/<artifact>.claim`
inside the intent directory, one small JSON file per artifact, scoped strictly
per-intent-per-artifact, never session-global. The claim gate is dormant
(allows) when no claim file exists for an artifact, so ordinary single-owner
work is unaffected; it engages, and denies, only when a second writer tries to
take a fresh claim someone else already holds. A stale or corrupt claim fails
open (the write proceeds, the claim yields) and the condition is surfaced in
`plastic-lock status`, which lists any live claims alongside the delivery
lock. See `plastic-lock claim`/`release-claim` and `docs/internals.md` for the
full mechanism.

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

Every code-touching intent gets its own git worktree named `{id}--{slug}`, and all code edits
for that intent happen only inside it. Plastic provisions the worktree deterministically: it
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

How one intent travels from boarding to Done, and what the lock, bridge, and gates do at
each station.

| Station | Delivered artifact | Lock and bridge steps | Pre-stage gate | Post-stage record |
|---|---|---|---|---|
| Start (board) | none (a procedure, not a stage) | `plastic-lock fix` self-heals stale, corrupt, or legacy state; arm acquires `delivery.lock` (O_EXCL, session-keyed), provisions the code worktree, writes the bridge cache | lock-gate denies any write into an active intent dir without this intent's lock; every deny names the resolving command | savepoint confirms the boarding station |
| What (create) | `<id>--<slug>.md`, born complete | no lock yet; no bridge | create-gate validates the proposed intent content (Write, Edit, and MCP edits) | savepoint `What` line; intent listed in INDEX `## Active` |
| Why | `spec.md` | owner writes refresh the lease (lock file mtime heartbeat) | gate-check requires the intent file with `## Intent` before spec.md; lock-gate admits only the owner or a delegate | savepoint `Why started`, `Why spec.md created` |
| How | `plan.md`, `actions/ACTION_N.md` (at least one), `checklist.md` | heartbeat on writes; the code gate stays closed until plan.md, checklist.md, and a real action file all exist | gate-check requires spec.md before plan.md, and plan.md plus a real actions/ACTION_N.md before checklist.md | savepoint `How started`, `How plan.md created`, `How checklist.md created`, `Exec started` |
| Exec | code on the intent branch, checklist checked off | heartbeat; code edits confined to the provisioned worktree; delegates write under the owner's lock; bash, interpreter, and MCP writes gated the same way | the five edit-path gates (savepoint-pre, lock-gate, code-gate with its stage and worktree rules, links-gate, create-gate) plus bash-gate for shell writes | checklist boxes; savepoint milestones |
| End (done) | mandatory `outcome.md` (`disposition: delivered\|abandoned`), INDEX moves to Completed or Abandoned | ordered End tail: verify, merge and remove worktrees, disarm clears `delivery.lock`, then the bridge is purge-eligible, and the QMD reindex runs LAST (after purge) | gate-check blocks outcome.md while checklist items are unchecked | savepoint `Done delivered` (or `abandoned`); takeover audits, if any, remain in savepoint.md |
| Maintenance (Future, Terminal, or Active-with-a-stale-or-no-lock) | `revisions.md` move-and-record entries | detects (never acquires) `delivery.lock`; defers and reports while the target's lock is FRESH (`Lock.fresh?`); a stale or absent lock is not-active, maintenance proceeds | none enforced by any gate; the maintenance tool or skill itself checks `Lock.fresh?` (see WORK vs MAINTENANCE in `references/maintenance-and-revisions.md`) | append-only, rule-tagged `revisions.md` entry written in the same operation as the change, or the change is refused; lands via a fresh branch off store main merged back as one closed op, never `git add -A` |
