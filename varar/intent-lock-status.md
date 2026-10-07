# plastic intent lock status

`plastic intent lock status ID` prints the delivery lock of one intent: the session that holds it, its mode, when it was taken and renewed, and whether it is still live. When the store's project names a repository, it also prints the intent's code worktree. With no lock it says so and offers `plastic auto ID`. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup | call | exit | result | next line |
| ----- | ---- | ---- | ------ | --------- |
| intent new Alpha | intent lock status 1 | 0 | lock: none | plastic auto 1 --project global |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- the CLI ships\n" ; sync up ; auto 1 | intent lock status 1 | 0 | lock: session s-1, mode auto, taken TIME, renewed TIME, live | plastic intent brief 1 --project global |
| none | intent lock status 9 | 1 | no intent 9 in this store | none |
