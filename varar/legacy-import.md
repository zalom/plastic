# Legacy store import

A store written before `store/index.json` keeps an `INDEX.md`. The first `plastic sync up`
imports it: it reads `INDEX.md` into intent and cluster rows, reads every file of every intent
folder, and prints the whole store. It keeps `INDEX.md` unless `migrate.remove_after_import` is on in
`config.yml`. Every intent folder must have an entry
and every entry a folder, or nothing is written. Each row copies a legacy store of two intents,
1 and its child 1a, into a fresh home, then runs the call through the storage kernel's
command line.

Each row gives the fixture, the call, the exit code, the result, the intents and the files of 1:

| fixture                        | call      | exit | result                                                                         | intents                                    | files of 1   |
| ------------------------------ | --------- | ---: | ------------------------------------------------------------------------------ | ------------------------------------------ | ------------ |
| as written                     | sync up   |    0 | imported INDEX.md: 2 intents and 0 clusters / imported metadata: 2 intents, 6 documents, 6 legacy files, 2 savepoint lines, 2 rulings, and 3 links / 14 files read   | 1 active since 2026-09-17, 1a future since 2026-09-17 | byte for byte |
| 1a without its own file        | sync up   |    0 | imported INDEX.md: 2 intents and 0 clusters / imported metadata: 2 intents, 5 documents, 6 legacy files, 2 savepoint lines, 2 rulings, and 2 links / 13 files read   | 1 active since 2026-09-17, 1a future undated | byte for byte |
| a folder with no entry         | sync up   |    1 | global: the import failed: store/9--stray has no entry in INDEX.md                                        | none                                       | byte for byte |
| as written                     | sync down |    1 | this store still has INDEX.md; run plastic sync up to import it first          | none                                       | byte for byte |
| imported                       | sync up   |    0 | none                                                                           | 1 active since 2026-09-17, 1a future since 2026-09-17 | byte for byte |
| imported, folder of 1 deleted  | sync down |    0 | 8 files printed                                                                | 1 active since 2026-09-17, 1a future since 2026-09-17 | byte for byte |
