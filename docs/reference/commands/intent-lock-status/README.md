# plastic intent lock status

Print the session that holds an intent's lock, and its worktree.

```sh
plastic intent lock status ID
```

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |

## The workflows of one call

![The workflows of one call of plastic intent lock status](workflows.svg)

Each box is a workflow. The words between the boxes say when the call moves on, and the last boxes say how the call ends.

## The events of one call, step by step

![The events of one call of plastic intent lock status](events.svg)

The boxes on the left run in order. The boxes on the right are the ways the call stops or ends at that step.

## What one call changes

This command changes nothing.

## What the agent workflow steps print

| Step | The text the agent gets |
| --- | --- |
| 4 | The instruction for the next step of the delivery: the owner's go-ahead while none is recorded, then the step the state of the intent calls for |

The command is `Plastic::Commands::Intent::Lock::Status`, in [`commands/intent/lock/status.rb`](../../../../lib/plastic/commands/intent/lock/status.rb).
