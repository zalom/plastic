# plastic sync down

`plastic sync down` prints the rows that changed into files. A record changed on both sides
since the last print is a conflict. A plain call writes nothing while one waits and exits 3,
naming every conflict. `--overwrite PATH` settles one record on the side of the direction,
`--overwrite` settles them all, and `--merge` applies the one-sided changes and leaves the
conflicts as they are. Each row starts from intent 1, Alpha, whose `spec.md` the rows already
hold, makes one change, then runs the call through the storage kernel's command line.

Each row gives the change, the call, the exit code, the result, the file and the row:

| change                         | call                                        | exit | result                                                                                                                                         | file      | row       |
| ------------------------------ | ------------------------------------------- | ---: | ---------------------------------------------------------------------------------------------------------------------------------------------- | --------- | --------- |
| spec row changed               | sync down                                   |    0 | printed store/1--alpha/spec.md                                                                                                                 | in rows   | in rows   |
| spec.md deleted                | sync down                                   |    0 | printed store/1--alpha/spec.md                                                                                                                 | # Spec    | # Spec    |
| intent folder deleted          | sync down                                   |    0 | printed store/1--alpha/1--alpha.md / printed store/1--alpha/graph.json / printed store/1--alpha/savepoint.md / printed store/1--alpha/spec.md | # Spec    | # Spec    |
| spec changed on both sides     | sync down                                   |    3 | changed on both sides since the last print, nothing written: store/1--alpha/spec.md; pass --overwrite PATH, --overwrite or --merge            | by hand   | in rows   |
| spec changed on both sides     | sync up                                     |    3 | changed on both sides since the last print, nothing written: store/1--alpha/spec.md; pass --overwrite PATH, --overwrite or --merge            | by hand   | in rows   |
| spec changed on both sides     | sync down --overwrite store/1--alpha/spec.md |   0 | printed store/1--alpha/spec.md                                                                                                                 | in rows   | in rows   |
| spec changed on both sides     | sync up --overwrite                         |    0 | read store/1--alpha/spec.md                                                                                                                    | by hand   | by hand   |
| both sides and own file row    | sync down --merge                           |    3 | printed store/1--alpha/1--alpha.md / changed on both sides since the last print, left as they are: store/1--alpha/spec.md; pass --overwrite PATH or --overwrite | by hand | in rows |
| spec changed on both sides     | sync down --overwrite store/9--nothing/spec.md |  1 | store/9--nothing/spec.md names no file and no rows of this store                                                                               | by hand   | in rows   |
| legacy store                   | sync down                                   |    1 | this store still has INDEX.md; run plastic sync up to import it first                                                                          | missing   | none      |
