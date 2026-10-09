# plastic intent new

`plastic intent new TITLE` opens an intent. It writes the intent's rows, then prints the
intent's folder and `store/index.json`. A call that cannot write stops before any row changes.
The rows below run the storage kernel's command line, which `bin/plastic` does not route to
yet, in a fresh home each time. ORIGIN stands for the installation id of that home.

Each row gives the store, the call, the exit code, the index, the files and what it says:

| store                | call                  | exit | index | files                                  | says                                                                                  |
| -------------------- | --------------------- | ---: | ----- | -------------------------------------- | ------------------------------------------------------------------------------------- |
| empty                | Build the thing       |    0 | 1     | graph.json, intent.md, savepoint.md | intent 1 has its rows and its printed files                                    |
| one intent           | Child --parent 1      |    0 | 1, 1a | graph.json, intent.md, savepoint.md | intent 1a has its rows and its printed files                                          |
| one intent           | Second --ref 1-ORIGIN |    0 | 1, 2  | graph.json, intent.md, savepoint.md | ref: intent 1 of this installation                                                    |
| empty                | Ticketed --ref ENG-12 |    0 | 1     | graph.json, intent.md, savepoint.md | ref: ENG-12                                                                         |
| empty                | Orphan --parent 9     |    1 | none  | none                                   | no intent 9 in this store to be the parent                                            |
| one intent           | Second --ref 5-ORIGIN |    1 | 1     | none                                   | no intent 5 of this installation for the ref                                          |
| empty                | Late --status done    |    1 | none  | none                                   | a new intent takes the status open, active, parked or future, not done                |
| legacy               | Too soon              |    1 | none  | none                                   | this store still has INDEX.md; run plastic sync up to import it first                 |
| index edited by hand | Second                |    1 | none  | none                                   | store/index.json changed by hand since the last print; run plastic sync up to read it first |
