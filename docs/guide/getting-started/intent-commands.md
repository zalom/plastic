# Intent commands

An intent is one piece of work with its own directory in a store. The `plastic intent`
commands carry it from its first line to its close. Every command prints a `next:` line that
names the command to run after it.

## The commands in order

The following table lists the commands in the order that an intent uses them:

| Command | What it does |
| ------- | ------------ |
| `plastic intent new "LINE"` | Creates the intent and files it under Active in `INDEX.md`. |
| `plastic intent show ID` | Prints the status, criteria, decisions, rulings and nodes of the intent. |
| `plastic intent spec ID` | Prints the rules for writing the specification, then the open decisions. |
| `plastic intent rule ID "TEXT"` | Records an owner ruling in the Insights section of the intent. |
| `plastic intent revise ID "LINE" [--why "TEXT"] [--dry-run]` | Rewrites the What and the Why of the intent after grilling. The old text stays as an earlier revision of the intent file. |
| `plastic intent approve ID` | Writes the owner go-ahead. `plastic auto ID` refuses an intent without it. |
| `plastic intent judge ID` | Prints the steps that start the judge. It takes no options. |
| `plastic intent verdict ID accept\|revise "TEXT"` | Records the verdict of the next review round, with the findings of the judge as the text. |
| `plastic intent end ID` | Closes the intent after its code is merged. It takes no options. |
| `plastic intent abandon ID` | Closes an intent that will not ship. It takes no options. |

The work of an intent runs through the `plastic node` commands: `node add ID TITLE --criterion KEY`,
`node claim`, `node done ID NODE TEXT`, `node fail`, `node ask`, `node impede` and `node resolve`.

Run `plastic intent` alone to print this list. Run `plastic help intent new` for the full
usage line of one command.

## Create an intent

The following command creates an intent from one line:

```bash
plastic intent new "Add a dark theme to the settings page"
```

The command takes the directory name from the first words of the line. The directory holds
`intent.md`, `spec.md`, `graph.json` and `outcome.md`. The following flags link the new intent
to other intents:

| Flag | Effect |
| ---- | ------ |
| `--parent ID` | Makes the intent a branch of another intent. |
| `--after ID` | Names an intent that this one grows out of, linked as a source. |
| `--ref REF` | Adds a ticket, a link, or another intent as `ID-ORIGIN`. |

## Close an intent

The session that delivered the intent closes it, after the code is merged. `plastic intent end ID`
needs every live node done, every criterion covered, and an accepted verdict at or after the
newest node change. It also needs the `Merged:` and `Architecture map:` records under
Verification in outcome.md, and with a required pull request the `Pull request:` and
`Approved:` records. An intent needs at least one live node. Small work needs no intent.

When something is missing, the command prints it and closes nothing. Exit code 3 means that the
step belongs to the owner: another session holds the intent, a second `revise` verdict was
recorded, or the pull request is not approved. Report it to the owner and stop.

`plastic intent abandon ID` closes an intent that will not ship. It hands over the revert
steps until outcome.md holds a `Reverted:` bullet under Verification.

Plastic does not merge. `plastic help tutorial` shows the merge and the close together.

## An ID that does not exist

The command exits with code 1 and names `plastic status`, which lists the intents that exist.
