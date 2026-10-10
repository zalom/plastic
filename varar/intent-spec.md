# plastic intent spec

`plastic intent spec ID` prints the grilling method, then lists each open decision of the intent's spec. A spec with no done criterion offers to write them first. A clear spec offers `plastic auto ID` only after the owner's go-ahead is recorded; before it, the call prints no next line and the output asks the owner. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the first line, the open lines and the next line:

| setup                                                                                                                                                  | call          | exit | first line                | open lines             | next line                  |
| ------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------- | ---- | ------------------------- | ---------------------- | -------------------------- |
| intent new Alpha                                                                                                                                       | intent spec 1 | 0    | # The grilling            | none                   | plastic sync up            |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- the CLI ships\n\n## Open Questions\n\n- which store wins\n" ; sync up | intent spec 1 | 0    | # The grilling            | open: which store wins | plastic intent rule 1 TEXT |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- the CLI ships\n" ; sync up                                            | intent spec 1 | 0    | # The grilling            | none                   | none                       |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- the CLI ships\n" ; sync up ; intent approve 1                         | intent spec 1 | 0    | # The grilling            | none                   | plastic auto 1             |
| none                                                                                                                                                   | intent spec 9 | 1    | no intent 9 in this store | none                   | none                       |
