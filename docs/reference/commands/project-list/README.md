# plastic project list

List the registered projects with their paths.

Lists the projects of projects.yml, each with its path, and marks the ones whose store folder is missing. It writes nothing.

```sh
plastic project list
```

## The events of one call, step by step

![The events of one call of plastic project list](events.svg)

The boxes on the left run in order. The boxes on the right are the ways the call stops or ends at that step.

## What one call changes

This command changes nothing.

The command is `Plastic::Commands::Project::List`, in [`list.rb:10`](../../../../lib/plastic/commands/project/list.rb#L10).
