# plastic intent verdict

Record the verdict of the next review round of an intent.

```sh
plastic intent verdict ID accept|revise TEXT
```

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |
| `accept|revise` | the verdict of this review round | |
| `TEXT` | what the review showed | |

## The workflows of one call

![The workflows of one call of plastic intent verdict](workflows.svg)

Each box is a workflow. The words between the boxes say when the call moves on, and the last boxes say how the call ends.

## The events of one call, step by step

![The events of one call of plastic intent verdict](events.svg)

The boxes on the left run in order. The boxes on the right are the ways the call stops or ends at that step.

## What one call changes

| What changes | Where | Reach |
| --- | --- | --- |
| The verdict of the review round is recorded | the work graph database, in the store folder | goes with the store |
| The files of the intent and the index of the store are rewritten | the store folder | goes with the store |

Goes with the store: the files of the store carry the change, and `plastic sync up` rebuilds it on another machine. The database files themselves stay on this machine.

The command is `Plastic::Commands::Intent::Verdict`, in [`commands/intent/verdict.rb`](../../../../lib/plastic/commands/intent/verdict.rb).
