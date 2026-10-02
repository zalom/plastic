# plastic edge remove

`plastic edge remove ID FROM TO` removes an edge. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup                                                                                                                       | call                | exit | result                       | next line                             |
| --------------------------------------------------------------------------------------------------------------------------- | ------------------- | ---- | ---------------------------- | ------------------------------------- |
| intent new Alpha ; node add 1 Build --criterion "tests pass" ; node add 1 Test --criterion "suite green" ; edge add 1 n2 n1 | edge remove 1 n2 n1 | 0    | edge: n2 to n1 removed       | plastic graph show 1 --project global |
| intent new Alpha ; node add 1 Build --criterion "tests pass"                                                                | edge remove 1 n2 n1 | 1    | no edge n2 to n1 in intent 1 | none                                  |
