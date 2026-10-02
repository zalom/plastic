# plastic roadmap add

`plastic roadmap add SLUG N ITEM` adds an item to batch N. `--after ITEM` makes it wait for another item. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup                                                                                                                             | call                                                             | exit | result                             | next line                                  |
| --------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- | ---- | ---------------------------------- | ------------------------------------------ |
| roadmap batch shop 1 --title Blockers --goal "guest checkout is safe"                                                             | roadmap add shop 1 guest --title "Lock down guest orders"        | 0    | item: guest Lock down guest orders | plastic roadmap show shop --project global |
| roadmap batch shop 1 --title Blockers --goal "guest checkout is safe" ; roadmap add shop 1 guest --title "Lock down guest orders" | roadmap add shop 1 pay --title "Charge on confirm" --after guest | 0    | item: pay Charge on confirm        | plastic roadmap show shop --project global |
| none                                                                                                                              | roadmap add shop 1 guest                                         | 1    | no batch 1 on roadmap shop         | none                                       |
| roadmap batch shop 1 --title Blockers --goal "guest checkout is safe" ; roadmap add shop 1 guest --title "Lock down guest orders" | roadmap add shop 1 pay --after nope                              | 1    | no item nope on roadmap shop       | none                                       |
