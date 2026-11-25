# plastic store backup list

List one store's backups with status and goal, flagging a missing or changed file.

```sh
plastic store backup list
```

## The events of one call, step by step

![The events of one call of plastic store backup list](events.svg)

The boxes on the left run in order. The boxes on the right are the ways the call stops or ends at that step.

## What one call changes

This command changes nothing.

The command is `Plastic::Commands::Store::Backup::List`, in [`commands/store/backup/list.rb`](../../../../lib/plastic/commands/store/backup/list.rb).
