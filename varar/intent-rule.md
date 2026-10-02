# plastic intent rule

`plastic intent rule ID TEXT` writes an owner ruling on an intent. `--supersedes` names the older ruling it replaces. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup                                                             | call                                               | exit | result                     | next line                               |
| ----------------------------------------------------------------- | -------------------------------------------------- | ---- | -------------------------- | --------------------------------------- |
| intent new Alpha                                                  | intent rule 1 "Flowbite styles every delivery"     | 0    | `ruling: D1`               | plastic intent brief 1 --project global |
| intent new Alpha ; intent rule 1 "Flowbite styles every delivery" | `intent rule 1 "Direct mode only" --supersedes D1` | 0    | `ruling: D2`               | plastic intent brief 1 --project global |
| intent new Alpha                                                  | `intent rule 1 "Direct mode only" --supersedes D7` | 1    | `no ruling D7 in intent 1` | none                                    |
| none                                                              | intent rule 9 "Direct mode only"                   | 1    | no intent 9 in this store  | none                                    |
