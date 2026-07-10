# Pick your mode: manual, guided, or auto

Who this is for: someone who has run one intent already and now wants to
choose, with clear eyes, how much control to keep over the next one.

After this guide you will know the real difference between the three ways of
working with Plastic, and which one fits the moment you are in.

## There is really only one question

When you board an intent (by saying "continue" or picking it), Plastic asks you
one question, exactly once: "auto or guided?" Everything about "modes" in
Plastic comes down to how you answer that single question, plus one path that
skips the question entirely.

## Guided

You say "guided." Plastic takes the lock on the intent, and from there you
start each stage yourself, typing its command, while the agent narrows its
thinking inside that one stage before handing back to you. Why closes with
`plastic-intent-speccing`, which turns your rulings into `spec.md`; the whole
intent closes with `plastic-intent-ending`, which writes the final outcome and
marks it done. At each stage you see what the agent is about to do and you
approve it before it moves on. This is the slower, closer-to-the-wheel option.
Choose it when the work is delicate, new, or you want to learn how Plastic
reasons about a problem before you trust it with something bigger.

## Auto

You say "auto." Plastic takes the lock and hands the whole cycle to an
autonomous agent. It runs Why, How, and Exec on its own, and only stops to ask
you something at a few designed moments: confirming a project path, or before
a destructive action with no safe undo. Choose it for well-scoped work you are
comfortable delegating.

## Manual (and why it is discouraged)

There is no separate "manual mode" built into Plastic. "Manual" here means
working completely outside the lifecycle skills: editing project files
directly without boarding an intent first. Plastic discourages this because it
skips the lock (so two sessions could collide) and it skips the gates that keep
work moving through What, Why, How, and Exec in order. If you find yourself
about to edit code without having boarded an intent, stop and create or board
one first.

So in practice, guided and auto are the same underlying path. Both take the
lock, both move through the same four stages, both end with the same kind of
result. The only difference is who steers each step: you (guided) or the agent
(auto). Manual is what happens when you skip boarding altogether, and Plastic's
advice is simple: don't.

## How to choose

- New to Plastic, or the work is unusual: choose guided.
- The work is small and well understood: choose auto.
- Either way, board the intent first. Never edit project code before that.

## What to read next

Once you are comfortable choosing a mode, read
[what-the-gates-are-telling-you.md](what-the-gates-are-telling-you.md) to
understand what happens if you (or an agent) try to skip a step.
