# plastic node release

`plastic node release ID NODE` puts a claimed or failed node back to open. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup                                                                                                        | call              | exit | result                                  | next line                                |
| ------------------------------------------------------------------------------------------------------------ | ----------------- | ---- | --------------------------------------- | ---------------------------------------- |
| intent new Alpha ; node add 1 Build --criterion "tests pass" ; node claim 1 n1                               | node release 1 n1 | 0    | node: n1 open                           | plastic node claim 1 n1 --project global |
| intent new Alpha ; node add 1 Build --criterion "tests pass" ; node claim 1 n1 ; node fail 1 n1 --reason red | node release 1 n1 | 0    | node: n1 open                           | plastic node claim 1 n1 --project global |
| intent new Alpha ; node add 1 Build --criterion "tests pass"                                                 | node release 1 n1 | 1    | node n1 is open; it cannot move to open | none                                     |
