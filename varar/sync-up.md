# plastic sync up

`plastic sync up` reads the files of a store that changed by hand into rows. A file that did not
change is left alone. A graph.json is read into rows when the rows hold no graph for its intent; a
graph.json that does not check is refused with its problems, and a later difference between the file and
the rows follows the conflict rule. An index.json whose content differs from the rows is read into rows; one that differs only in its layout is left alone. A call that cannot read stops before any row changes. Each row starts
from intent 1, Alpha, whose `spec.md` the rows already hold, makes one change by hand, then
calls `plastic sync up` through the storage kernel's command line.

Each row gives the change, the exit code, the result and the rows:

| change                          | exit | result                                                                                         | rows                 |
| ------------------------------- | ---: | ---------------------------------------------------------------------------------------------- | -------------------- |
| none                            |    0 | none                                                                                           | # Spec               |
| spec.md edited                  |    0 | read store/1--alpha/spec.md                                                                    | # Spec, edited       |
| graph.json given a node | 0 | read store/1--alpha/graph.json | n1 needs n2 |
| graph.json that does not check | 1 | files that cannot be read into rows, the others were read: | |
| title renamed in index.json | 0 | read store/index.json | Alpha, renamed |
| cluster added in index.json | 0 | read store/index.json | Core holds 1 |
| savepoint.md emptied            |    0 | read store/1--alpha/savepoint.md                                                               | 0 savepoint lines    |
| a folder with no intent file | 1 | intent folders that could not be read, the others were read: | # Spec |
| index.json of another origin | 0 | none | Alpha |
| index.json that does not parse | 0 | none | Alpha |
