# plastic hook stop

Stop: stamp the turn, renew locks, run the stop gate.

```sh
plastic hook stop
```

## The events of one call, step by step

![The events of one call of plastic hook stop](events.svg)

The boxes on the left run in order. The boxes on the right are the ways the call stops or ends at that step.

## What one call changes

| What changes | Where | Reach |
| --- | --- | --- |
| The last turn of the session is stamped and its live locks are renewed | the local database, in the home folder | stays on this machine |

The command is `Plastic::Hooks::Stop`, in [`stop.rb:14`](../../../../lib/plastic/hooks/stop.rb#L14).
