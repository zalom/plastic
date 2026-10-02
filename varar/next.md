# plastic next

`plastic next` picks the intent in play and offers the one command to run next. The offer moves with the intent, from writing its spec to claiming its nodes. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup                                                                                                                                                                  | call | exit | result | next line                                 |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---- | ---- | ------ | ----------------------------------------- |
| none                                                                                                                                                                   | next | 0    | none   | plastic intent new TITLE --project global |
| intent new Alpha                                                                                                                                                       | next | 0    | none   | plastic intent spec 1 --project global    |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- the CLI ships\n" ; sync up                                                            | next | 0    | none   | plastic auto start 1 --project global     |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- the CLI ships\n" ; sync up ; auto start 1                                             | next | 0    | none   | plastic intent brief 1 --project global   |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- the CLI ships\n" ; sync up ; auto start 1 ; node add 1 Build --criterion "tests pass" | next | 0    | none   | plastic graph ready 1 --project global    |
