# plastic intent archive --revert

`plastic intent archive ID --revert` restores an archived intent's exact directory snapshot. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup                                               | call             | exit | result                   | next line                               |
| --------------------------------------------------- | ---------------- | ---- | ------------------------ | --------------------------------------- |
| intent new Later --status future ; intent archive 1 | intent archive 1 --revert | 0    | intent: 1 restored       | plastic intent show 1 --project global |
| intent new Later --status future                    | intent archive 1 --revert | 1    | intent 1 is not archived | none                                    |
