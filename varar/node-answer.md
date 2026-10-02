# plastic node answer

`plastic node answer ID NODE --answer TEXT` answers a parked node and opens it again. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup                                                                                                                      | call                                    | exit | result                                  | next line                                |
| -------------------------------------------------------------------------------------------------------------------------- | --------------------------------------- | ---- | --------------------------------------- | ---------------------------------------- |
| intent new Alpha ; node add 1 Build --criterion "tests pass" ; node claim 1 n1 ; node park 1 n1 --question "which harness" | node answer 1 n1 --answer "Claude Code" | 0    | node: n1 open                           | plastic node claim 1 n1 --project global |
| intent new Alpha ; node add 1 Build --criterion "tests pass"                                                               | node answer 1 n1 --answer "Claude Code" | 1    | node n1 is open; it cannot move to open | none                                     |
