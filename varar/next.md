# plastic next

`plastic next` picks the intent in play and offers the one command to run next. The offer moves with the intent, from writing its spec to claiming its nodes. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup                                                                                                                                                                  | call | exit | result | next line                                 |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---- | ---- | ------ | ----------------------------------------- |
| none                                                                                                                                                                   | next | 0    | none   | none |
| intent new Alpha                                                                                                                                                       | next | 0    | none   | plastic intent spec 1 --project global    |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- the CLI ships\n" ; sync up                                                            | next | 0    | none   | plastic auto 1 --project global     |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- the CLI ships\n" ; sync up ; auto 1 | next | 0 | 1. Before you plan, fetch the architecture map as current as possible with an architecture mapping tool such as Enola, or map the code yourself; Plastic runs no tool. Read the intent's goal and done criteria. Add work with plastic node add 1 TITLE --criterion TEXT, then add dependencies with plastic edge add. Use plastic graph ready 1 after the plan is recorded. | none |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- the CLI ships\n" ; sync up ; auto 1 ; node add 1 Build --criterion "tests pass" | next | 0    | none   | plastic node claim 1 n1 --project global    |
