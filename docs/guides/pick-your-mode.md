# Pick your mode: direct, thinking, or auto

Who this is for: someone who has run one request through Plastic already and now wants to
choose, with clear eyes, how much of the next one to do in the conversation and how much to
hand to an agent.

After this guide you will know the real difference between the three ways of working with
Plastic, and which one fits the moment you are in.

## There is really only one question

Where does "how to execute" come from? That is the whole difference between the modes. Plastic
never asks you to pick one; it reads the answer off your prompt.

## Direct

You type what you want and it happens, in this session, right away. Direct is the default. If
the prompt is not clear enough to run, Plastic asks one question, then runs. The work is
recorded after it is done, in the day ledger (one per calendar day) or in the intent your
session is pointed at. Choose it, or rather let it choose itself, for anything you could
describe as a named operation on a known target: rename this, add a check there, fix that
line. The owner's rule of thumb is about five minutes of work.

## Thinking

You are not sure yet what the right change is, or the change is too big to hold in one prompt.
Thinking is a conversation first: Plastic asks one question at a time, records each ruling you
make as an insight in the intent, and then writes the action files that say how the work will
be done. After that it works exactly as in direct. Choose it when the work is delicate, new,
or you want to reason it through before anything is built. Ask to be grilled if you want the
questions to be hard.

## Auto

You say "auto" on a registered intent with a clear prompt. Plastic hands the whole cycle to a
background team: a lead that writes the record and an executor that builds, under a lock and
in its own git worktree, with a reviewer only if you ask for one. It stops to ask you something
at a few designed moments: confirming a project path, or before an action with no safe undo.
Choose it for well-scoped work you are comfortable delegating.

## What stays the same

All three modes write the same record: the intent's `## Insights`, `checklist.md`, and
`savepoint.md` while the work happens, and `spec.md`, `plan.md`, `actions/`, and `outcome.md`
backfilled when it ends. Nothing blocks a write in any mode. The only difference is who steers
and where the plan comes from: your prompt (direct), a conversation (thinking), or an agent
team (auto).

## How to choose

- You can name the operation and the target: direct. Just type it.
- You need to think it through first, or the work is larger than a prompt: thinking.
- The intent is registered and the prompt is clear: auto.

## What to read next

Once you are comfortable choosing a mode, read
[reading-the-ledgers.md](reading-the-ledgers.md) to see where each mode writes its work down.
