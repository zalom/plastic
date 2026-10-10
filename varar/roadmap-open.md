# plastic roadmap open

`plastic roadmap open SLUG ITEM` makes the intent for a ready item and links the two. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup                                                                                                                                                                                                                   | call                    | exit | result                         | next line              |
| ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------- | ---- | ------------------------------ | ---------------------- |
| roadmap new shop ; roadmap batch shop 1 --title Blockers --goal "guest checkout is safe" ; roadmap add shop 1 guest --title "Lock down guest orders"                                                                    | roadmap open shop guest | 0    | intent: 1                      | plastic intent brief 1 |
| roadmap new shop ; roadmap batch shop 1 --title Blockers --goal "guest checkout is safe" ; roadmap add shop 1 guest --title "Lock down guest orders" ; roadmap add shop 1 pay --title "Charge on confirm" --needs guest | roadmap open shop pay   | 3    | item pay is blocked, not ready | none                   |
| roadmap new shop ; roadmap batch shop 1 --title Blockers --goal "guest checkout is safe" ; roadmap add shop 1 guest --title "Lock down guest orders"                                                                    | roadmap open shop nope  | 1    | no item nope on roadmap shop   | none                   |
