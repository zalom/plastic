# plastic roadmap edge remove

`plastic roadmap edge remove SLUG FROM TO` removes the needs edge by which TO needs FROM. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup                                                                                                                                                                                                                   | call                               | exit | result                               | next line                 |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------- | ---- | ------------------------------------ | ------------------------- |
| roadmap new shop ; roadmap batch shop 1 --title Blockers --goal "guest checkout is safe" ; roadmap add shop 1 guest --title "Lock down guest orders" ; roadmap add shop 1 pay --title "Charge on confirm" --needs guest | roadmap edge remove shop guest pay | 0    | edge: guest to pay removed           | plastic roadmap show shop |
| roadmap new shop ; roadmap batch shop 1 --title Blockers --goal "guest checkout is safe" ; roadmap add shop 1 guest --title "Lock down guest orders"                                                                    | roadmap edge remove shop guest pay | 1    | no edge guest to pay on roadmap shop | none                      |
