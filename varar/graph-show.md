# plastic graph show

`plastic graph show ID` prints every node and edge from the rows. It reads and writes no file. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup                                                                                                                       | call         | exit | result                                                    | next line                              |
| --------------------------------------------------------------------------------------------------------------------------- | ------------ | ---- | --------------------------------------------------------- | -------------------------------------- |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- [tests-pass] tests pass\n- [suite-green] suite green\n" ; sync up ; node add 1 Build --criterion tests-pass ; node add 1 Test --criterion suite-green ; edge add 1 n2 n1 | graph show 1 | 0    | node: n1 open Build / node: n2 open Test / edge: n2 to n1 | plastic graph ready 1 --project global |
| intent new Alpha                                                                                                            | graph show 1 | 0    | none                                                      | plastic graph ready 1 --project global |
| none                                                                                                                        | graph show 9 | 1    | no intent 9 in this store                                 | none                                   |
