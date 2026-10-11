# Project and roadmap commands

A project is one code directory with its own store of intents. A roadmap orders the intents
of a store into batches, as rows in the store's work graph. These commands register projects
and keep roadmaps.

## Project commands

The following table shows each project command and what it does:

| Command | What it does |
| ------- | ------------ |
| `plastic project list` | Lists every store on this machine, with its path. |
| `plastic project new SLUG PATH` | Registers the directory at `PATH` as a project in `projects.yml` and makes its store. |
| `plastic project links` | Lists the links that name an intent or a ruling the store lacks. |

## Register a project

Run the command with a short name and the path of the project's directory. The name uses
lowercase letters, digits and hyphens. `global` is taken.

```
plastic project new acme ~/code/acme
```

The command prints a `project` row with the name and the path, and its `next:` line names
`plastic intent new TITLE --project acme`. It fails when the path is not a directory. It
refuses with exit 3 when the name is registered at another path. The same name at the same
path again changes nothing.

## Roadmap commands

A roadmap has a name, its `SLUG`, and holds numbered batches of items. Each item can need
other items, and each item opens one intent. The following table shows each roadmap command
and what it does:

| Command | What it does |
| ------- | ------------ |
| `plastic roadmap new NAME [--title TITLE] [--goal GOAL]` | Makes a roadmap. |
| `plastic roadmap batch SLUG N [--title TITLE] [--goal GOAL] [--done TEXT]` | Writes the goal and the done criteria of batch `N`. |
| `plastic roadmap add SLUG N ITEM [--title TITLE] [--goal GOAL] [--done TEXT] [--needs ITEM]` | Adds an item to batch `N`, with the items it needs. |
| `plastic roadmap show SLUG [--batch N]` | Prints the batches and items of a roadmap. |
| `plastic roadmap next SLUG [--batch N]` | Prints the first ready item, or what is in its way. |
| `plastic roadmap open SLUG ITEM` | Opens the intent of a ready item. |
| `plastic roadmap drop SLUG ITEM [--dry-run]` | Marks an item dropped. |
| `plastic roadmap check SLUG` | Lists the loops, the edges that name a missing item, and the items with no intent. |
| `plastic roadmap log SLUG TEXT...` | Appends a log line, stamped with the session. |
| `plastic roadmap edge remove SLUG FROM TO [--dry-run]` | Removes one needs edge. |
