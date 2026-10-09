# plastic intent unarchive

`plastic intent unarchive ID` restores an archived intent's exact directory snapshot. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup                                               | call               | exit | result                   | next line             |
| --------------------------------------------------- | ------------------ | ---- | ------------------------ | --------------------- |
| intent new Later --status future ; intent archive 1 | intent unarchive 1 | 0    | intent: 1 unarchived     | plastic intent show 1 |
| intent new Later --status future                    | intent unarchive 1 | 1    | intent 1 is not archived | none                  |
