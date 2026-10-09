# plastic roadmap batch

`plastic roadmap batch SLUG N` adds batch N to a roadmap that `roadmap new` made. `--title` and `--goal` describe the batch. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup                                                                                    | call                                                                  | exit | result                 | next line                 |
| ---------------------------------------------------------------------------------------- | --------------------------------------------------------------------- | ---- | ---------------------- | ------------------------- |
| roadmap new shop                                                                         | roadmap batch shop 1 --title Blockers --goal "guest checkout is safe" | 0    | batch: shop 1 Blockers | plastic roadmap show shop |
| roadmap new shop ; roadmap batch shop 1 --title Blockers --goal "guest checkout is safe" | roadmap batch shop 2 --title Payments                                 | 0    | batch: shop 2 Payments | plastic roadmap show shop |
| roadmap new shop ; roadmap batch shop 1 --title Blockers --goal "guest checkout is safe" | roadmap batch shop 1 --done "guest orders need a login"               | 0    | batch: shop 1 Blockers | plastic roadmap show shop |
| none                                                                                     | roadmap batch shop 1 --title Blockers                                 | 1    | no roadmap shop        | plastic roadmap new shop  |
