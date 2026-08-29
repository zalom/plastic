# What the gates are telling you

> The gates this guide describes were removed in 2.0 (intent 302), and the skills it names to unblock them were merged or removed in 2.0 (intent 304). It stays for readers of a Plastic 1.x install.

Who this is for: someone who just tried to do something in Plastic, got
stopped with a message they do not recognize, and wants to know what to do
next.

After this guide you will be able to read any Plastic gate message and know
the exact command (or one of two commands) that resolves it.

The examples below show Claude Code's slash form. On Codex CLI, invoke the same fix with a
dollar prefix instead (for example `$plastic-doctor`), or let Codex pick one implicitly by
matching its description.

## What a gate is

Every write runs through five gates (savepoint-pre, lock, code, links,
create), and shell commands pass a bash gate. Savepoint-pre only records
state and never denies; every other gate is a hard gate that stops the
action outright. You cannot proceed until you fix the thing the message
names.

Gates guard writes, locks, and structure. They never guard reads. Reads and
searches over the intent stores are never blocked, by any gate, ever.

## The hard gates, verbatim

**No lock held yet.** You tried to write to an intent's files without boarding
it first.

> no delivery lock held for intent {id}; run /plastic-intent-continuing to lock
> and begin

Fix: run `/plastic-intent-continuing`.

**Lock held by another session.** Someone (or something) else is already
delivering this intent.

> intent {id} delivery lock is held by session {owner}. Back off; if you are
> the owner's subagent, the owner must run: plastic-lock delegate --intent-dir
> {dir} --session <your-session-id>. Inspect with /plastic-doctor check the
> lock status

Fix: if you are alone on this intent, this deny is rare. Plastic relaxes it
automatically once it confirms exactly one live session is working. If it does
fire, inspect with `/plastic-doctor check the lock status`; if you are a
subagent, the owning session runs the `plastic-lock delegate` command shown in
the message.

**Stale lock.** The lock file exists but its owner has gone quiet.

> intent {id} has a stale delivery lock (owner {owner}); run /plastic-doctor
> reclaim the lock to take it over, or /plastic-doctor fix the lock

Fix: run `/plastic-doctor reclaim the lock` if you are taking the intent over
from a session that stopped responding (this is recorded). Use
`/plastic-doctor fix the lock` instead only if you are the rightful owner
coming back to your own stale lock.

**Corrupt lock file.** The lock file cannot be read.

> delivery.lock for intent {id} is unreadable; run /plastic-doctor fix the lock

Fix: run `/plastic-doctor fix the lock`.

**Code gate.** You (or an agent) tried to edit project code before a plan
existed. The message reads, punctuation aside:

> intent {id} has not reached How: write plan.md + checklist.md and at least
> one real actions/ACTION_N.md before editing project code. Run plastic-auto
> or plastic-intent-planning first. (blocked edit: {path}) (removed in 2.0, intent 304)

Fix: `plastic-auto` or `plastic-intent-planning`. Another choice of two: either (removed in 2.0, intent 304)
one writes the missing plan and checklist, then editing is allowed.

**Create gate.** Someone tried to write an intent file by hand instead of
through the tool that creates them.

> PLASTIC CREATE GATE: {basename} is not a valid intent:
>   {validation errors}
> Create intents via new-intent / plastic-intent-creating; do not
> hand-author them.

Fix: `new-intent` (the underlying script) or `plastic-intent-creating` (the
skill that wraps it). A choice of two again.

## The honest summary

Of the six gate messages quoted above, four name one clear fixing command
(no lock, lock held, stale lock, corrupt lock). Two name a choice of two
commands (code gate, create gate). The links gate and the bash gate deny the
same way (the bash gate reuses the code and lock gate messages for shell
writes). No read or search is ever blocked by anything in Plastic.

So the rule to remember is not "every deny names the one command." It is:
every deny names the command, or the short choice of commands, that gets you
moving again, and reading things never gets stopped.

## What to read next

Once a gate makes sense, read
[reading-a-delivered-intent.md](reading-a-delivered-intent.md) to learn how to
check what an intent actually shipped once it is done.
