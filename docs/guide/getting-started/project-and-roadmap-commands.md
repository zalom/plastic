# Project and roadmap commands

A project is one code directory with its own store of intents. A roadmap is one file that
orders intents into batches. These commands register projects and read roadmaps.

## Project commands

The following table shows each project command and what it does:

| Command | What it does |
| ------- | ------------ |
| `plastic project list` | Lists every store on this machine, with its path. |
| `plastic project new SLUG --path PATH [--parent ID]` | Registers the directory at `PATH` as a project, makes its store and checks it. |
| `plastic project links [--dry-run]` | Rebuilds the Links section of every intent from its frontmatter. |

## Register a project

1. Make the project directory, and write an `AGENTS.md` file in it.
1. Run the command with a short name and the path:

   ```
   plastic project new acme --path ~/code/acme
   ```

The command prints `OK: acme` when the store passes its check. It registers nothing when the
directory is missing, when the directory has no `AGENTS.md`, or when the name is taken. In
each case it exits with status 1 and says which one happened.

## Roadmap commands

A roadmap file lives in the `roadmaps` directory of a store, and its name without `.md` is
its `SLUG`. The following table shows each roadmap command and what it does:

| Command | What it does |
| ------- | ------------ |
| `plastic roadmap next` | Names the roadmap that is most worth continuing. |
| `plastic roadmap show SLUG` | Prints the state of one roadmap: its goal, its progress and its entries. |
| `plastic roadmap log SLUG EVENT "TEXT"` | Appends one dated line to the roadmap's ledger. |
| `plastic roadmap check SLUG` | Checks the Graph section of the roadmap file. |

`EVENT` is one word from a fixed list, such as `dispatched`, `merged` or `handoff`. A word
outside the list exits with status 1, and the message prints the whole list.

To make a new roadmap, copy the roadmap template into the `roadmaps` directory and edit it
by hand. No command writes the file.
