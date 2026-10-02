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


After the records are ready, submit the acceptance:

```sh
plastic intent end ID --judge tool --evidence completion.json
```

Replace ID with the intent identifier and choose the judge that performed the
acceptance. Relative evidence paths start inside that intent's folder. Paths and
symbolic links outside the folder are refused.

If an existing done node has no verification, check it again and record the result:

```sh
plastic node done ID NODE --repair --judge tool --findings "Actual findings"
```

The repair preserves the done state and attempt count. Ordinary node completion
requires a claimed node and nonempty findings.
