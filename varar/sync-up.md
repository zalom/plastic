# plastic sync up

`plastic sync up` reads the files of a store that changed by hand into rows. A file that did not
change is left alone. The generated graph.json view is never imported, and a call that cannot read stops before any row changes. Each row starts
from intent 1, Alpha, whose `spec.md` the rows already hold, makes one change by hand, then
calls `plastic sync up` through the storage kernel's command line.

Each row gives the change, the exit code, the result and the rows:

| change                          | exit | result                                                                                         | rows                 |
| ------------------------------- | ---: | ---------------------------------------------------------------------------------------------- | -------------------- |
| none                            |    0 | none                                                                                           | # Spec               |
| spec.md edited                  |    0 | read store/1--alpha/spec.md                                                                    | # Spec, edited       |
| graph.json given a node | 0 | none | |
| title renamed in index.json     |    0 | read store/index.json                                                                          | Alpha, renamed       |
| cluster added in index.json     |    0 | read store/index.json                                                                          | Core holds 1         |
| savepoint.md emptied            |    0 | read store/1--alpha/savepoint.md                                                               | 0 savepoint lines    |
| a folder with no intent row     |    1 | store/7--stray has no intent row and no entry in store/index.json; add one or remove the folder | # Spec              |
| index.json of another origin    |    1 | store/index.json lists 1 of origin beef; a store holds only its own intents                    | Alpha                |
| index.json that does not parse  |    1 | store/index.json does not parse                                                                | Alpha                |
