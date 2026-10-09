# plastic intent end

`plastic intent end ID` closes a delivered intent. It takes no options. It reads the rows
and `outcome.md`, closes the intent when they allow it, and otherwise prints what is missing.

The session that delivered the intent closes it, after its code is merged. There is no
lock handover: a live lock of another session refuses the close with exit 3. An intent
needs at least one live node. Small work needs no intent, because the session rows in
local.db record it. Work that must be recognized gets an intent with a small graph.

## What the close checks

| Check | Closes only when |
| ----- | ---------------- |
| Nodes | Every live node is done with findings. |
| Criteria | Every done criterion key of `spec.md` is covered by a done live node, and no node carries a key the spec lacks. |
| Decisions | Every decision is resolved. |
| Verdict | The latest judge verdict is `accept` and is not older than the newest change of a live node. |
| Outcome | `outcome.md` is substantive and stored by sync up. |
| Pull request | With `review.pull_request` set to `required` (the default), `outcome.md` has a `Pull request:` bullet and, before the close, an `Approved:` bullet. With `off`, neither is asked for. |
| Merge and map | `outcome.md` has a `Merged:` and an `Architecture map:` bullet. |

A done criterion in `spec.md` carries a key in square brackets, such as
`- [ ] [ships] Ships`. A key has two to 32 lowercase letters, digits and dashes. A
criterion with no key uses its full text as its key. A node names its key with
`plastic node add ID TITLE --criterion KEY`.

## What happens when something is missing

- Records the agent can write, and a missing verdict, come back as a handoff with exit 0.
  The command lists them and closes nothing. When no accepted verdict counts, it names
  `plastic intent judge ID`.
- A second `revise` verdict, or a call after two verdicts, is the owner's step: exit 3.
- With `required`, a pull request without its `Approved:` bullet is the owner's step:
  exit 3. Wait for the person's approval, record it, and run the command again.
- When the records hold but `outcome.md` lacks the merge records, the command hands the
  agent two steps and closes nothing. Add these bullets under `## Verification` in
  outcome.md, run `plastic sync up`, and call the command again:

```
- Pull request: <link or number>
- Approved: <who approved it, and when>
- Merged: <branch> into <base> at <commit or pull request>
- Architecture map: <tool> at <source revision>
```

Plastic runs no version control command. It records what you write.

## The judge

```sh
plastic intent judge ID
plastic intent verdict ID accept "Findings of the judge"
```

`intent judge` prints the steps that start a reasoning judge agent. The judge records its
verdict with `plastic intent verdict ID accept|revise TEXT`, the text being its findings.
A `revise` verdict tells the agent to add a fix node with `plastic node add`. A review has
two rounds.

## The close

A close writes the completion row with the judge `verdict` and the evidence built from the
rows: each criterion key with its done nodes and their findings. It sets the intent to done
and releases the delivery lock. Then it prints the intent's files and hands the agent the
wind-down steps: stop the processes and agents the intent started. Plastic stops none of them.
A second call on a closed intent exits 1 and leaves the first completion row.

If an existing done node has no findings, record them again:

```sh
plastic node done ID NODE "Actual findings"
```

The second call preserves the done state and attempt count. Ordinary node completion
requires a claimed node and nonempty findings.

## Abandon an intent

```sh
plastic intent abandon ID
```

This closes an open, active, parked or future intent that will not ship. It takes no
options. Until `outcome.md` holds a `Reverted:` bullet under `## Verification`, the command
hands the agent the revert steps and closes nothing:

```
- Reverted: <what was undone, or nothing delivered>
```

Then the close sets the status `abandoned` and releases the lock. The disposition is
`superseded` when a `supersedes` link from another intent points at the intent, otherwise
`cancelled`. The close needs no criteria, nodes, verdict or merge record, and writes no
completion row. Calling it again only finishes the lock cleanup.
