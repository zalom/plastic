# plastic intent end

Close a delivered intent once its verdict, nodes and outcome allow it, or print what is missing.

```sh
plastic intent end ID
```

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |

## The workflows of one call

![The workflows of one call of plastic intent end](workflows.svg)

Each box is a workflow. The words between the boxes say when the call moves on, and the last boxes say how the call ends.

## The events of one call, step by step

![The events of one call of plastic intent end](events.svg)

The boxes on the left run in order. The boxes on the right are the ways the call stops or ends at that step.

## What one call changes

| What changes | Where | Reach |
| --- | --- | --- |
| The intent is marked done, its completion is saved and its driver claim is released | the work graph database, in the store folder | goes with the store |
| The cost of a run of the intent that has none is filled from the harness record when it holds one | the work graph database, in the store folder | goes with the store |
| The files of the intent and the index of the store are rewritten | the store folder | goes with the store |

Goes with the store: the files of the store carry the change, and `plastic store sync up` rebuilds it on another machine. The database files themselves stay on this machine.

## What the agent workflow steps print

| Step | The text the agent gets |
| --- | --- |
| 4 | Complete these recorded prerequisites: \<requirements> |
| 5 | No accepted review counts yet. Run plastic intent judge \<intent id>; the judge records the verdict of the next review round with plastic intent verdict. Then run plastic intent end \<intent id> again. |
| 6 | \<delivery found> Record the delivery of intent \<intent id> under ## Verification in \<intent folder>/outcome.md with one line. For code, use version control, such as Git, as the project's AGENTS.md or CLAUDE.md defines it, or as the project's history shows when neither does: merge the pull request of intent \<intent id> into the intent's base, and leave it open only when the owner asked. \<template found> Then add '- Merged: \<branch> into \<base> at \<commit or pull request>', or '- Committed: \<branch> at \<commit>' when the project commits straight to its branch. Add '- Delivered: resources/output/\<path> because \<reason>' only for work that no version control holds: put a report of the work in \<intent folder>/resources/output/reports and record it with plastic intent report \<intent id> PATH, put other files in \<intent folder>/resources/output/files, and name them in the line. Then run plastic store sync up and plastic intent end \<intent id> again. Plastic runs no version control command; it records what you write. |
| 10 | Stop the processes and the agents that intent \<intent id> started: servers, watchers, background jobs and subagents. Plastic runs none of them and stops none of them. |

The command is `Plastic::Commands::Intent::End`, in [`commands/intent/end.rb`](../../../../lib/plastic/commands/intent/end.rb).
