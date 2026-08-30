# Using Plastic with Claude Code

Who this is for: someone ready to use Plastic day to day inside Claude Code,
past their first single intent, who wants to see the bigger picture.

After this guide you will understand the three modes in more depth, and how
Plastic ships a whole batch of related work through a roadmap.

## The ladder: direct, thinking, and auto

You already met the three modes in [pick-your-mode.md](pick-your-mode.md).
Here is what each one feels like in practice, day to day.

Direct is most of a day. You ask for a change, the agent makes it in the same
session, verifies it (the tests, the page, or you), and the request lands as a
line in the day ledger with a commit behind it. There is nothing to approve
and nothing to type next; the next prompt is the next item.

Thinking is a conversation before the work. The agent asks one question at a
time and records each answer as an insight in the intent, then writes the
action files that say how the work will be done, then works as in direct. You
can close the conversation into `spec.md` with `/plastic-intent-speccing`, and
the intent with `/plastic-intent-ending` once Exec is done. This is
deliberately slower. It is the right choice when you want to watch each
decision as it happens.

In auto mode, a background team takes a registered intent and keeps moving,
except at a small number of hard stops: confirming a project path, or before an
action with no safe way back. You get the full story as it happens, but you
are only pulled in when it truly matters.

One way to describe the difference: the agent always carries the machinery,
the record, the actual work of each item. In direct and thinking modes, you
also carry the decisions. In auto mode, the agent carries those too, except at
the few moments built to need you.

## Roadmap-driven delivery

Once you have more than one intent to ship, Plastic has a way to plan and
track them together: a roadmap. A roadmap is one file (`roadmaps/{slug}.md`,
next to your `INDEX.md`) with four parts:

- A short title and one-line description of what the roadmap is for.
- A **Goal**: a plain-language paragraph describing what "done" looks like for
  the whole batch.
- **Batches**: an ordered list of groups of intents. Intents in the same
  batch can run in parallel; batches run one after another. Each entry mirrors
  the intent's real status, and the index is always the final word if the two
  ever disagree.
- A **Log**: a running, dated diary of what happened, written so a person
  outside the work can follow along.

Nothing new needs to run this: no new lock, no new hook. It is just a file
that gets read and edited as work moves forward.

### A real example

The roadmap that shipped this very guide is a working example:
`roadmaps/stable-1-0.md`. Its Goal reads, in short: every intent in the plan
delivered or clearly abandoned, the test suite green, and a 1.0 release cut
together with the project's owner. It is organized into seven waves, from
early foundations through trust fixes for new users, process simplifications,
this batch of first-run guides, a pending human decision, longer engineering
work, and a longer-term intelligence track. Its Log is a dated, plain-language
account of each delivery as it happened, written the way a project lead would
brief someone checking in on progress.

## A word on "loop" and "/goal"

Two Claude Code harness commands, not Plastic skills, keep a session moving
without you restarting it each time. `/loop` repeats a prompt or command on a
fixed time interval, until you stop it or Claude decides the work is done.
`/goal` works differently: you give it a condition instead of an interval, it
sets that as the completion condition, and Claude keeps working, turn after
turn, until a fast checker model confirms from what Claude has actually
reported that the condition holds. `/goal` never reads files on its own, so
the condition has to name a check Claude's own output can prove.

The tutorial's projects-and-roadmaps track walks `/goal` in practice: you hand
it a roadmap's `## Goal` and current batch as the condition, and it drives
through that batch and stops on its own once the condition is met. Both
commands ship with Claude Code itself; Plastic supplies the roadmap and its
batches, the harness supplies the command that drives through them. On a
harness without these commands, the same roadmap-driven delivery still
works: just tell the agent to deliver it in auto mode instead.

## What to read next

If you have not already, start from
[your-first-intent-in-10-minutes.md](your-first-intent-in-10-minutes.md) to
run your first intent, or revisit
[pick-your-mode.md](pick-your-mode.md) to choose how closely to steer your
next one.
