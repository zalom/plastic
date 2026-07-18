# What the gates are telling you

Who this is for: someone who just tried to do something in Plastic, got
stopped with a message they do not recognize, and wants to know what to do
next.

After this guide you will be able to read any Plastic gate message and know
the exact command (or one of two commands) that resolves it.

The examples below show Claude Code's slash form. On Codex CLI, invoke the same fix with a
dollar prefix instead (for example `$plastic-doctor`), or let Codex pick one implicitly by
matching its description.

## Two kinds of gate

Plastic has HARD gates and one ADVISORY gate. This distinction matters:

- **HARD gates** (lock, code, create, worktree) stop the action outright. You
  cannot proceed until you fix the thing the message names.
- **The ADVISORY gate** (retrieval) never stops anything. It only adds a
  reminder. Reads and searches over the intent stores are never blocked, by
  any gate, ever.

Most first-time confusion comes from not knowing which kind you hit. If your
read or search still ran and you just got extra text with it, that was the
advisory gate. Nothing failed.

## The hard gates, verbatim

**No lock held yet.** You tried to write to an intent's files without boarding
it first.

> no delivery lock held for intent {id}; run /plastic-intent-starting to lock
> and begin

Fix: run `/plastic-intent-starting`.

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
existed.

> intent {id} has not reached How: write plan.md + checklist.md before
> editing project code. Run plastic-auto or plastic-intent-planning first.
> (blocked edit: {path})

Fix: `plastic-auto` or `plastic-intent-planning`. Another choice of two: either
one writes the missing plan and checklist, then editing is allowed.

**Create gate.** Someone tried to write an intent file by hand instead of
through the tool that creates them.

> PLASTIC CREATE GATE: {basename} is not a valid intent:
>   {validation errors}
> Create intents via new-intent / plastic-intent-creating; do not
> hand-author them.

Fix: `new-intent` (the underlying script) or `plastic-intent-creating` (the
skill that wraps it). A choice of two again.

## The one advisory gate

**Retrieval gate.** This one never blocks anything. If it fires, your search
still ran; you just get an extra note:

> PLASTIC advisory: {reason} (this search ran; the hint is not a block)

The reason is usually a nudge to search through the proper tool instead of
scanning files directly. It is a suggestion, not a wall.

## The honest summary

Of the six real hard-gate messages, four name one clear fixing command
(no lock, lock held, stale lock, corrupt lock). Two name a choice of two
commands (code gate, create gate). The advisory retrieval gate never denies
at all, and no read or search is ever blocked by anything in Plastic.

So the rule to remember is not "every deny names the one command." It is:
every deny names the command, or the short choice of commands, that gets you
moving again, and reading things never gets stopped.

## What to read next

Once a gate makes sense, read
[reading-a-delivered-intent.md](reading-a-delivered-intent.md) to learn how to
check what an intent actually shipped once it is done.
