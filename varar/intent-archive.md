# plastic intent archive

`plastic intent archive ID` removes a done, abandoned or future intent's files from the store. Its rows stay, so `intent restore` can write the files again. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup                            | call             | exit | result                                                            | next line                                 |
| -------------------------------- | ---------------- | ---- | ----------------------------------------------------------------- | ----------------------------------------- |
| intent new Later --status future | intent archive 1 | 0    | intent: 1 archived                                                | plastic intent restore 1 --project global |
| intent new Alpha                 | intent archive 1 | 3    | intent 1 is open; only done, abandoned and future intents archive | none                                      |
| none                             | intent archive 9 | 1    | no intent 9                                                       | none                                      |
