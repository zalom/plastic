# plastic store migration list

Print the ledger rows of one store and what a down would undo now.

```sh
plastic store migration list
```

## The events of one call, step by step

![The events of one call of plastic store migration list](events.svg)

The boxes on the left run in order. The boxes on the right are the ways the call stops or ends at that step.

## What one call changes

This command changes nothing.

The command is `Plastic::Commands::Store::Migration::List`, in [`commands/store/migration/list.rb`](../../../../lib/plastic/commands/store/migration/list.rb).
