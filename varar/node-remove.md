# plastic node remove

`plastic node remove ID NODE` removes a node. Its edges stay as rows, so the history of the graph stays whole. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup                                                                          | call                                         | exit | result                                        | next line                              |
| ------------------------------------------------------------------------------ | -------------------------------------------- | ---- | --------------------------------------------- | -------------------------------------- |
| intent new Alpha ; node add 1 Build --criterion "tests pass"                   | node remove 1 n1 --reason "folded into Test" | 0    | node: n1 removed                              | plastic graph ready 1 --project global |
| intent new Alpha ; node add 1 Build --criterion "tests pass" ; node claim 1 n1 | node remove 1 n1                             | 1    | node n1 is claimed; it cannot move to removed | none                                   |
| intent new Alpha ; node add 1 Build --criterion "tests pass"                   | node remove 1 n9                             | 1    | no node n9 in intent 1                        | none                                   |
| none                                                                           | node remove 9 n1                             | 1    | no intent 9 in this store                     | none                                   |
