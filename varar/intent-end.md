# plastic intent end

`plastic intent end ID` gives the harness checked instructions to finish the work,
verify each done criterion, and write an outcome. It does not infer acceptance
from done nodes. The session that delivered the intent closes it, after its code
is merged. Nothing hands the lock to another session.

Before the close, outcome.md records the merge and the architecture map as two
bullets under `## Verification`:

```markdown
## Verification
- Merged: plastic/1--alpha into alpha at abc123
- Architecture map: enola at abc123
```

Without both bullets, the command hands the agent the merge-check steps and closes
nothing. Plastic runs no version control command; it records what the agent writes.

Submit the acceptance with `--judge tests`, `--judge tool`, `--judge agent`, or
`--judge owner`, and `--evidence completion.json`. The evidence file lives inside the
intent folder. It maps each criterion key from the spec to a nonempty description of
its verification. A done criterion takes its key in square brackets: `- [ ] [ships] Ships`.
A criterion without a key uses its full text as its key.

```json
{
  "ships": "Fixture acceptance verified"
}
```

The judge attests to this evidence. Plastic records the attestation and outcome
hash; it does not rerun the verification. Use owner only for explicit owner
acceptance. Closure requires finished work, node verification, resolved decisions,
the two verification bullets, and a substantive outcome stored by sync up. An
intent needs at least one live node. It releases the delivery lock.
Repeating closure preserves the first acceptance record and completes lock cleanup.

`plastic intent end ID --abandoned` closes an intent that will never ship. It needs
only an outcome.md that says why. It takes no `--judge` or `--evidence`, writes no
completion record, and works on an open, active, parked or future intent.

The rows below use a disposable fixture with one verified node and outcome.
Each row gives the closure case, the exit code, the status, the completion records and the next line:

| closure case | exit | status | completion records | next line |
| --- | --- | --- | --- | --- |
| request verification | 0 | active | 0 | none |
| missing criterion evidence | 1 | active | 0 | none |
| unverified close | 0 | active | 0 | none |
| accept delivery | 0 | done | 1 | none |
| repeat closure | 0 | done | 1 | none |
| abandon | 0 | abandoned | 0 | none |
