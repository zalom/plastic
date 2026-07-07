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
npx -y @zalom/plastic@beta install --claude
```

This sets up a folder at `~/.plastic/` that holds your intents, an index of all
of them, and the rules your agent will follow.

## Step 2: Create your first intent

Just say what you want, in plain words. For example: "I want to add a `--version`
flag to the CLI." You do not need to write a special file yourself. Plastic
recognizes this as a new piece of work and scaffolds an intent file for you
behind the scenes. Do not try to write the intent file by hand. Plastic always
creates it through its own tool, so the file is complete and valid from the start.

## Step 3: Board the intent

Say "continue," or point at the intent you just created. Plastic will take a
lock on it first (so no other session works on the same intent at the same
time), and then ask you one question: "auto or guided?"

- **Guided** means you walk through each stage with the agent, approving as you go.
- **Auto** means the agent runs the whole cycle by itself and only stops you at
  a few important moments.

For your first intent, try auto. It is the fastest way to see the whole shape
of Plastic in one pass.

## Step 4: Say "auto"

The agent now runs Why, then How, then Exec, one after another, without you
needing to steer each step. When it finishes, it writes a file called
`outcome.md` that records exactly what was delivered. That file is the proof
your work is done. Your intent also moves to the "Completed" section of the
index, so you can find it again later.

That is the whole loop: install once, describe what you want, board it, say
"auto," and read the result.

## What to read next

Now that you have seen the full cycle once, read
[pick-your-mode.md](pick-your-mode.md) to understand the difference between
guided and auto, and when to choose each one.
