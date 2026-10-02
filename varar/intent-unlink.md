# plastic intent unlink

`plastic intent unlink ID KIND TARGET` removes a link that `intent link` made. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup                                                      | call                    | exit | result                    | next line                          |
| ---------------------------------------------------------- | ----------------------- | ---- | ------------------------- | ---------------------------------- |
| intent new Alpha ; intent new Beta ; intent link 1 cites 2 | intent unlink 1 cites 2 | 0    | link: 1 cites 2 removed   | plastic sync down --project global |
| intent new Alpha ; intent new Beta                         | intent unlink 1 cites 2 | 1    | no cites link from 1 to 2 | none                               |
