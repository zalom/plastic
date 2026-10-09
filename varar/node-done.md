# plastic node done

`plastic node done ID NODE TEXT` marks a claimed node done. Nonempty findings record what the work showed; a node is verified by its findings alone. Calling it again on a done node replaces its findings. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup                                                                                                                                                                             | call                                                | exit | result                                  | next line             |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- | ---- | --------------------------------------- | --------------------- |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- [tests-pass] tests pass\n" ; sync up ; node add 1 Build --criterion tests-pass ; node claim 1 n1 | node done 1 n1 "12 runs green"                      | 0    | node: n1 done                           | plastic graph ready 1 |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- [tests-pass] tests pass\n" ; sync up ; node add 1 Build --criterion tests-pass                   | node done 1 n1 "Example verification"               | 1    | node n1 is open; it cannot move to done | none                  |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- [tests-pass] tests pass\n" ; sync up ; node add 1 Build --criterion tests-pass ; node claim 1 n1 | node done 1 n1 --judge tests "Example verification" | 2    | invalid option: --judge                 | none                  |
