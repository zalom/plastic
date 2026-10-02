# plastic intent end

`plastic intent end ID` gives the harness checked instructions to finish the work,
verify each done criterion, and write an outcome. It does not infer acceptance
from done nodes. Submit the acceptance with `--judge tests`, `--judge tool`,
`--judge agent`, or `--judge owner`, and `--evidence completion.json`.

The evidence file lives inside the intent folder. It maps each exact criterion
from the spec to a nonempty description of its verification:

```json
{
  "Ships": "Fixture acceptance verified"
}
```

The judge attests to this evidence. Plastic records the attestation and outcome
hash; it does not rerun the verification. Use owner only for explicit owner
acceptance. Closure requires finished work, node verification, resolved decisions,
and a substantive outcome stored by sync up. It releases the delivery lock.
Repeating closure preserves the first acceptance record and completes lock cleanup.

The rows below use a disposable fixture with one verified node and outcome.
Each row gives the closure case, the exit code, the status, the completion records and the next line:

| closure case | exit | status | completion records | next line |
| --- | --- | --- | --- | --- |
| request verification | 0 | active | 0 | none |
| missing criterion evidence | 1 | active | 0 | none |
| accept delivery | 0 | done | 1 | none |
| repeat closure | 0 | done | 1 | none |
