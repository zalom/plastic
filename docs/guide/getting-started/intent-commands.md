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
| `plastic intent revise ID "LINE" [--why "TEXT"] [--dry-run]` | Rewrites the What and the Why of the intent after grilling. The old text stays as an earlier revision of the intent file. |
| `plastic intent note ID "TEXT"` | Appends a note to the savepoint ledger of the intent. |
| `plastic intent step ID` | On a graph intent, runs the next ready step of the graph; this session must hold the delivery lock. On a checklist intent, prints the next unchecked item and runs nothing. |
| `plastic intent answer ID --node NODE --decision "TEXT"` | Answers a step that waits for a decision. |
| `plastic intent verify ID` | Runs the per-intent doctor check and the em-dash guard, and prints the diffstat of the code branch. Its doctor check fails while `outcome.md` is still a placeholder, so write `outcome.md` before you verify. |
| `plastic intent end ID --judge tool --evidence completion.json` | Closes the intent after its code is merged. Use `--abandoned` to close it without delivery. |

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

The session that delivered the intent closes it, after the code is merged. `plastic intent end ID`
asks for the merge and architecture map records under Verification in outcome.md, then for
evidence by criterion key. `--abandoned` closes an intent that will not ship; outcome.md says why.
An intent needs at least one live node. Small work needs no intent.

Exit code 3 means that another session holds the intent. Report it to the owner and stop.

A delivered close also exits 1 and names the reason in three cases. In the first two, it
writes nothing:

- The code branch `plastic/ID--slug` or its worktree exists, and the branch is not merged, or the
  repository checkout is still on it. Merge the branch, then close again.
- The intent is an untouched scaffold: the lifecycle files are placeholders and no work was
  recorded. Do the work, or close it with `--abandoned`.
- `outcome.md` lists fewer delivered rows than there are action files. This check runs after
  Plastic fills in placeholder records, so `outcome.md` or an action file may already be
  written. `INDEX.md`, the savepoint ledger, and the store commit stay unchanged.

Plastic does not merge. `plastic help tutorial` shows the merge and the close together.

## An ID that does not exist

The command exits with code 1 and names `plastic status`, which lists the intents that exist.
