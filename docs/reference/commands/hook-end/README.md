# plastic hook end

SessionEnd: set the session's end time and reason.

```sh
plastic hook end
```

## The events of one call, step by step

![The events of one call of plastic hook end](events.svg)

The boxes on the left run in order. The boxes on the right are the ways the call stops or ends at that step.

## What one call changes

| What changes | Where | Reach |
| --- | --- | --- |
| The end time and the reason are written to the session row | the local database, in the home folder | stays on this machine |
| The node claims and the driver claims of the session are released | the work graph database, in the store folder | stays on this machine |
| With backup.daily on, every store takes its end-of-day backup, which replaces the earlier one of the day | the backups folder, in the store folder | stays on this machine |

The command is `Plastic::Hooks::End`, in [`hooks/end.rb`](../../../../lib/plastic/hooks/end.rb).
