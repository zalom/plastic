# plastic node ask

`plastic node ask ID NODE TEXT` moves a claimed node to needs_info with a question for the owner. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup                                                                                                                                                                             | call                                | exit | result                                        | next line                      |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------- | ---- | --------------------------------------------- | ------------------------------ |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- [tests-pass] tests pass\n" ; sync up ; node add 1 Build --criterion tests-pass ; node claim 1 n1 | node ask 1 n1 "which harness first" | 0    | node: n1 needs_info                           | plastic node resolve 1 n1 TEXT |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- [tests-pass] tests pass\n" ; sync up ; node add 1 Build --criterion tests-pass                   | node ask 1 n1 "which harness first" | 1    | node n1 is open; it cannot move to needs_info | none                           |
