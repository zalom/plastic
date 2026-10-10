# plastic intent link

`plastic intent link ID KIND TARGET` links one intent to another. KIND is cites, supersedes, answers, source or chain. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup                              | call                  | exit | result                                               | next line         |
| ---------------------------------- | --------------------- | ---- | ---------------------------------------------------- | ----------------- |
| intent new Alpha ; intent new Beta | intent link 1 cites 2 | 0    | link: 1 cites 2                                      | plastic sync down |
| intent new Alpha                   | intent link 1 chain 9 | 1    | no intent 9 in this store                            | none              |
| intent new Alpha ; intent new Beta | intent link 1 likes 2 | 2    | KIND takes cites, supersedes, answers, source, chain | none              |
