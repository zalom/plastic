# plastic intent end

`plastic intent end ID` gives the harness checked instructions to finish the work,
verify each done criterion, and write an outcome. It does not infer acceptance
from done nodes. Submit the acceptance with `--judge tests`, `--judge tool`,
`--judge agent`, or `--judge owner`, and `--evidence completion.json`.

The session that delivered the intent closes it, after its code is merged. There is no
lock handover: a live lock of another session refuses the close with exit 3. An intent
needs at least one live node. Small work needs no intent, because the session rows in
local.db record it. Work that must be recognized gets an intent with a small graph.

Before the close, check the merge. When the records hold but outcome.md lacks them, the
command hands the agent two steps and closes nothing. Add these bullets under
`## Verification` in outcome.md, run `plastic sync up`, and call the command again:

```
- Merged: <branch> into <base> at <commit or pull request>
- Architecture map: <tool> at <source revision>
```

Plastic runs no version control command. It records what you write.

The evidence file lives inside the intent folder. Each done criterion in spec.md carries a
key in square brackets, such as `- [ ] [ships] Ships`. A key has two to 32 lowercase
letters, digits and dashes. A criterion with no key uses its full text as its key. The
file maps each key to a nonempty description of its verification:

```json
{
  "ships": "Fixture acceptance verified"
}
```

A refused file names the missing keys, the extra keys and the keys with blank text.

The judge attests to this evidence. Plastic records the attestation and outcome
hash; it does not rerun the verification. Use owner only for explicit owner
acceptance. Closure requires finished work, node verification, resolved decisions,
and a substantive outcome stored by sync up. It releases the delivery lock.
Repeating closure preserves the first acceptance record and completes lock cleanup.

After the records are ready, submit the acceptance:

```sh
plastic intent end ID --judge tool --evidence completion.json
```

Replace ID with the intent identifier and choose the judge that performed the
acceptance. Relative evidence paths start inside that intent's folder. Paths and
symbolic links outside the folder are refused.

If an existing done node has no verification, check it again and record the result:

```sh
plastic node done ID NODE "Actual findings"
```

The second call preserves the done state and attempt count. Ordinary node completion
requires a claimed node and nonempty findings.

## Abandon an intent

```sh
plastic intent end ID --abandoned
```

This closes an open, active, parked or future intent that will not ship. outcome.md must
say why. The close needs no criteria, nodes, judge, evidence or merge record, writes no
completion row, and releases the lock. With `--judge` or `--evidence` it is a usage error
(exit 2). Calling it again only finishes the lock cleanup.
