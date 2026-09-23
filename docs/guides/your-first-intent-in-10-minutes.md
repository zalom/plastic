# Your first intent in 10 minutes

Who this is for: someone who has never used Plastic before and wants to see it work,
start to finish, right now.

After this guide you will have installed Plastic, created one small piece of work
(an "intent"), and watched an agent deliver it on its own.

The 10 minutes assumes a small, well-scoped first task. Plastic calls this an
S-tier intent: one file or one small mechanism, the kind of change that takes an
hour or two, not a redesign. Pick something like that for your first try. A good
example: "add a `--version` flag that prints the current version."

## What is an intent?

An intent is one unit of work, written down in one file, that moves through four
stages: What (the idea), Why (the plan of attack), How (the concrete steps), and
Exec (the code gets written). Plastic tracks every piece of work this way instead
of letting an agent jump straight into editing files.

## Step 1: Install Plastic

Run this once:

```
npx -y @zalom/plastic install --claude
```

This sets up a folder at `~/.plastic/` that holds your intents, an index of all
of them, and the rules your agent will follow.

## Step 2: Create your first intent

Register the repository once, then create the intent from one line:

```
plastic project new my-app --path "$PWD"
plastic intent new "Add a --version flag that prints the current version"
```

Do not write the intent file by hand. `plastic intent new` scaffolds it, so the file is
complete and valid from the start. Every command ends with a `next:` line that names the
command to run after it.

## Step 3: Hand it to auto

Ask your agent to deliver the intent in auto mode. The agent runs `plastic auto take ID`,
which takes the delivery lock (so no other team works on the same intent at the same time)
and makes a Git worktree for the code. It then spawns the `plastic-enforcer` lead, which
writes the record, dispatches an executor, and reviews by risk. It stops to ask you something
only at a few important moments.

To do the same cycle yourself, one step at a time, follow `plastic help tutorial`.

For your first intent, auto is the fastest way to see the whole shape of Plastic in
one pass. The other two modes, direct (type the change and it happens) and thinking
(a conversation first), are explained in [pick-your-mode.md](pick-your-mode.md).

## Step 4: Read the result

The agent now runs Why, then How, then Exec, one after another, without you
needing to steer each step. When it closes the intent with `plastic intent end`, the close writes
`outcome.md`, which records what was delivered. The close refuses code that is not
merged, so the merge comes first. That file is the proof
your work is done. Your intent also moves to the "Completed" section of the
index, so you can find it again later.

That is the whole loop: install once, create the intent, hand it to auto, and
read the result.

## What to read next

Now that you have seen the full cycle once, read
[pick-your-mode.md](pick-your-mode.md) to understand the difference between
guided and auto, and when to choose each one.
