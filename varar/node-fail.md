# plastic node fail

`plastic node fail ID NODE --reason TEXT` marks a claimed node failed. The next claim prints the reason. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup                                                                          | call                                       | exit | result                                    | next line                                  |
| ------------------------------------------------------------------------------ | ------------------------------------------ | ---- | ----------------------------------------- | ------------------------------------------ |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- [tests-pass] tests pass\n" ; sync up ; node add 1 Build --criterion tests-pass ; node claim 1 n1 | node fail 1 n1 --reason "the suite is red" | 0    | node: n1 failed                           | plastic node release 1 n1 --project global |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- [tests-pass] tests pass\n" ; sync up ; node add 1 Build --criterion tests-pass                   | node fail 1 n1 --reason red                | 1    | node n1 is open; it cannot move to failed | none                                       |
