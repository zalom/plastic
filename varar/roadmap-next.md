# plastic roadmap next

`plastic roadmap next SLUG` lists the items ready to start and offers the first one. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup                                                                                                                                                                                                | call              | exit | result          | next line                                         |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------- | ---- | --------------- | ------------------------------------------------- |
| roadmap batch shop 1 --title Blockers --goal "guest checkout is safe" ; roadmap add shop 1 guest --title "Lock down guest orders" ; roadmap add shop 1 pay --title "Charge on confirm" --needs guest | roadmap next shop | 0    | pay: blocked    | plastic roadmap start shop guest --project global |
| roadmap batch shop 1 --title Blockers --goal "guest checkout is safe"                                                                                                                                | roadmap next shop | 0    | none            | plastic roadmap show shop --project global        |
| none                                                                                                                                                                                                 | roadmap next shop | 1    | no roadmap shop | none                                              |
