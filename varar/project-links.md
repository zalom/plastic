# plastic project links

`plastic project links` lists the links of the store whose local end names an intent or a ruling the store does not hold, and prints the count when it lists any. A ref with a store prefix names another store and is not checked. It writes nothing. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup | call | exit | result | next line |
| ----- | ---- | ---- | ------ | --------- |
| none | project links | 0 | none | plastic status |
| intent new Alpha ; intent new Beta ; intent link 1 cites 2 | project links | 0 | none | plastic status |
| intent new Alpha ; intent link 1 cites other:5 | project links | 0 | none | plastic status |
