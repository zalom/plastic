# Preview a sync

`plastic sync up --dry-run` runs the same import and sync against a disposable copy.
The original store stays unchanged. Run `plastic sync up` to apply the changes to
that store. Use `--project` to select another store.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup | call              | exit | result                                               | next line       |
| ----- | ----------------- | ---- | ---------------------------------------------------- | --------------- |
| none  | sync up --dry-run | 0    | preview complete; the original store was not changed | plastic sync up |
