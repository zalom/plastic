# plastic intent approve

`plastic intent approve ID` writes the owner's go-ahead for an intent: one row, written once. A second call changes nothing and exits 0. It fails for a missing, done or abandoned intent. `plastic auto ID` refuses an intent without the row. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup                                                                                                                          | call             | exit | result                           | next line             |
| ------------------------------------------------------------------------------------------------------------------------------ | ---------------- | ---- | -------------------------------- | --------------------- |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- the CLI ships\n" ; sync up                    | intent approve 1 | 0    | approved: 1                      | plastic auto 1        |
| intent new Alpha                                                                                                               | intent approve 1 | 1    | intent 1 names no done criterion | plastic intent spec 1 |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- the CLI ships\n" ; sync up ; intent approve 1 | intent approve 1 | 0    | approved: 1                      | plastic auto 1        |
| none                                                                                                                           | intent approve 9 | 1    | no intent 9 in this store        | none                  |
