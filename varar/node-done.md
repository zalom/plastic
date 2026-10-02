# plastic node done

`plastic node done ID NODE --judge JUDGE` marks a claimed node done. The judge is tests, tool, agent or owner, and `--findings` records what the judge saw. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup                                                                          | call                                                    | exit | result                                    | next line                              |
| ------------------------------------------------------------------------------ | ------------------------------------------------------- | ---- | ----------------------------------------- | -------------------------------------- |
| intent new Alpha ; node add 1 Build --criterion "tests pass" ; node claim 1 n1 | node done 1 n1 --judge tests --findings "12 runs green" | 0    | node: n1 done                             | plastic graph ready 1 --project global |
| intent new Alpha ; node add 1 Build --criterion "tests pass"                   | node done 1 n1 --judge tests                            | 1    | node n1 is open; it cannot move to done   | none                                   |
| intent new Alpha ; node add 1 Build --criterion "tests pass" ; node claim 1 n1 | node done 1 n1 --judge nobody                           | 2    | --judge takes tests, tool, agent or owner | none                                   |
