# plastic auto start

`plastic auto start ID` takes the delivery lock for the session and sets the intent active. It refuses an intent with no done criterion or an open decision, because those are owner steps. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup                                                                                                                                                  | call         | exit | result                                                   | next line                               |
| ------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------ | ---- | -------------------------------------------------------- | --------------------------------------- |
| intent new Alpha                                                                                                                                       | auto start 1 | 3    | intent 1 names no done criterion                         | none                                    |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- the CLI ships\n\n## Open Questions\n\n- which store wins\n" ; sync up | auto start 1 | 3    | intent 1 has an open decision; run plastic intent spec 1 | none                                    |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- the CLI ships\n" ; sync up                                            | auto start 1 | 0    | none                                                     | plastic intent brief 1 --project global |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- the CLI ships\n" ; sync up ; auto start 1                             | auto start 1 | 0    | none                                                     | plastic intent brief 1 --project global |
| none                                                                                                                                                   | auto start 9 | 1    | no intent 9 in this store                                | none                                    |
