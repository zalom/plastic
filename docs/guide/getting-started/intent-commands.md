# Intent commands

An intent is one piece of work with its own directory in a store. The `plastic intent`
commands carry it from its first line to its close. Every command prints a `next:` line that
names the command to run after it.

## The commands in order

The following table lists the commands in the order that an intent uses them:

| Command | What it does |
| ------- | ------------ |
| `plastic intent new "LINE"` | Creates the intent and files it under Active in `INDEX.md`. |
| `plastic intent show ID` | Prints the state screen of the intent. |
| `plastic intent spec ID` | Prints the state screen, then the rules for writing the specification. |
| `plastic intent rule ID "TEXT"` | Records an owner ruling in the Insights section of the intent. |
| `plastic intent note ID "TEXT"` | Appends a note to the savepoint ledger of the intent. |
| `plastic intent step ID` | On a graph intent, runs the next ready step of the graph; this session must hold the delivery lock. On a checklist intent, prints the next unchecked item and runs nothing. |
| `plastic intent answer ID --node NODE --decision "TEXT"` | Answers a step that waits for a decision. |
| `plastic intent verify ID` | Runs the per-intent doctor check and the em-dash guard, and prints the diffstat of the code branch. On a checklist intent it fails until `outcome.md` exists, which `plastic intent end` writes. |
| `plastic intent end ID --delivered --summary "TEXT"` | Closes the intent. Use `--abandoned` to close it without delivery. |

Run `plastic intent` alone to print this list. Run `plastic help intent new` for the full
usage line of one command.

## Create an intent

The following command creates an intent from one line:

```bash
plastic intent new "Add a dark theme to the settings page"
```

The command takes the directory name from the first five words of the line. Pass
`--slug SLUG` to choose the name. The following flags link the new intent to other intents:

| Flag | Effect |
| ---- | ------ |
| `--parent ID` | Makes the intent a branch of another intent. |
| `--sources IDS` | Names the intents that this one came from, separated by commas. |
| `--tags TAGS` | Adds tags, separated by commas. |

## Close an intent

`plastic intent end` needs `--delivered` or `--abandoned`, and a `--summary`. Without a summary
the command exits with code 2 and prints what a summary must say. `--note "TEXT"` adds text to
the line in `INDEX.md`. `--dry-run` previews the close and writes nothing.

Exit code 3 means that another session holds the intent. Report it to the owner and stop.

A delivered close also exits 1, writes nothing, and names the reason, in three cases:

- The code branch `plastic/ID--slug` or its worktree exists, and the branch is not merged, or the
  repository checkout is still on it. Merge the branch, then close again.
- The intent is an untouched scaffold: the lifecycle files are placeholders and no work was
  recorded. Do the work, or close it with `--abandoned`.
- `outcome.md` lists fewer delivered rows than there are action files.

Plastic does not merge. `plastic help tutorial` shows the merge and the close together.

## An ID that does not exist

The command exits with code 1 and names `plastic status`, which lists the intents that exist.
