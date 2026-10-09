# plastic intent revise

`plastic intent revise ID LINE` rewrites an intent's What, and `--why TEXT` its Why. The old text stays as an earlier revision of the intent's file, and `--dry-run` prints the change and writes nothing. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup            | call                                                      | exit | result                                                             | next line                                           |
| ---------------- | --------------------------------------------------------- | ---- | ------------------------------------------------------------------ | --------------------------------------------------- |
| intent new Alpha | `intent revise 1 "Beta" --dry-run`                        | 0    | what was: Alpha / what: Beta                                       | plastic intent revise 1 Beta                        |
| intent new Alpha | `intent revise 1 "Beta" --why "The goal moved" --dry-run` | 0    | what was: Alpha / what: Beta / why was: none / why: The goal moved | plastic intent revise 1 Beta --why The\ goal\ moved |
| intent new Alpha | `intent revise 1 "Alpha"`                                 | 1    | intent 1 already reads this What and Why; nothing to change        | none                                                |
| none             | `intent revise 9 "Beta"`                                  | 1    | no intent 9 in this store                                          | none                                                |
