# plastic intent rule

Write an owner decision, an addition to one with --adds, or a rewrite of one with --rewrites.

```sh
plastic intent rule ID TEXT [--adds DECISION_ID] [--rewrites DECISION_ID]
```

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ID` | the intent | |
| `TEXT` | the decision, in the owner's words | |
| `--adds DECISION_ID` | a decision this one adds to, such as `D1`; it takes the next number under it, such as `D1.1` |  |
| `--rewrites DECISION_ID` | a decision whose text this one replaces; the additions of that decision are removed |  |

## The events of one call, step by step

![The events of one call of plastic intent rule](events.svg)

The boxes on the left run in order. The boxes on the right are the ways the call stops or ends at that step.

## What one call changes

| What changes | Where | Reach |
| --- | --- | --- |
| The decision is added to the rulings of the intent, or its text is replaced and its additions removed | the knowledge graph database, in the store folder | goes with the store |
| The files of the intent and the index of the store are rewritten | the store folder | goes with the store |

Goes with the store: the files of the store carry the change, and `plastic store sync up` rebuilds it on another machine. The database files themselves stay on this machine.

The command is `Plastic::Commands::Intent::Rule`, in [`commands/intent/rule.rb`](../../../../lib/plastic/commands/intent/rule.rb).
