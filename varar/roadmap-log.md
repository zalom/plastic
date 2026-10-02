# plastic roadmap log

`plastic roadmap log SLUG TEXT` adds a dated line to a roadmap's log. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup                                                                 | call                               | exit | result               | next line                                  |
| --------------------------------------------------------------------- | ---------------------------------- | ---- | -------------------- | ------------------------------------------ |
| roadmap batch shop 1 --title Blockers --goal "guest checkout is safe" | roadmap log shop "batch 1 planned" | 0    | log: batch 1 planned | plastic roadmap show shop --project global |
| none                                                                  | roadmap log shop "batch 1 planned" | 1    | no roadmap shop      | none                                       |
