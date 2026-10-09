# plastic node add

`plastic node add ID TITLE --criterion KEY` adds an open node to an intent's work graph. The key must name a done criterion of the intent's synced `spec.md`; a node without one is a usage error, and an unknown key or a missing spec is a failure. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup            | call                                                           | exit | result                    | next line                                |
| ---------------- | -------------------------------------------------------------- | ---- | ------------------------- | ---------------------------------------- |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- [tests-pass] tests pass\n" ; sync up | node add 1 Build --criterion tests-pass                      | 0    | node: n1                  | plastic node claim 1 n1 --project global |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- [tests-pass] tests pass\n" ; sync up | node add 1 Build --criterion tests-pass --input docs/plan.md | 0    | node: n1                  | plastic node claim 1 n1 --project global |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- [tests-pass] tests pass\n" ; sync up | node add 1 Build --criterion nope | 1 | criterion "nope" is not a done criterion key of spec.md; the keys are: tests-pass | none |
| intent new Alpha | node add 1 Build --criterion tests-pass | 1 | intent 1 has no synced spec.md; write its done criteria, then run plastic sync up | none |
| intent new Alpha | node add 1 Build                                               | 2    | missing --criterion       | none                                     |
| none             | node add 9 Build --criterion "tests pass"                      | 1    | no intent 9 in this store | none                                     |
