# Choice screen

A command that needs the person to pick from a list asks through the choice screen. The person
picks, never the agent, and no option lets an agent pick for the person.

| Where the command runs | What the person sees | How the call ends |
| --- | --- | --- |
| A terminal: standard input and output are both terminals, no `--json` | The list, with some items already picked | The picked items, or no change |
| No terminal, or `--json` | A numbered list, printed by the call | `next:` with the command and `<answer>` |

## In a terminal

| Key | What it does |
| --- | --- |
| Up and Down | Move between items |
| Space | Pick or unpick the item |
| Ctrl+A | Pick every item |
| Enter | Confirm the picked items |
| Ctrl+C | Leave with no change |

## From inside an agent

The call prints the question, the numbered list and the answer rule, then stops:

```
question:  Which harnesses?
choices:   1  [x] claude
           2  [ ] codex
answer:    answer with numbers separated by commas (1,2), a for all, or q to leave with no change

next: plastic init <answer>
because: the person picks, not the agent; ask the person, then run the command again with their answer
```

`[x]` marks an item that starts picked. The agent shows the list to the person and runs the
command again with the person's answer in place of `<answer>`:

| Answer | Meaning |
| --- | --- |
| `1,2` | Pick items 1 and 2 |
| `a` | Pick every item |
| `q` | Leave with no change |

An answer with a number that is not on the list, or any other word, is a usage error (exit 2)
that names the valid numbers or the answer rule. With `--json` the same rows come back as one
document, with `next` holding the command.
