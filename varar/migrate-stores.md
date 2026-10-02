# plastic migrate stores

`plastic migrate stores` reads each legacy store into rows: intents, rulings, links and roadmaps. `--dry-run` reports what it would read, and `--apply` writes the rows. It keeps the legacy files unless `migrate.remove_after_import` is on in `config.yml`. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup  | call                     | exit | result                                                                                                                                                        | next line                      |
| ------ | ------------------------ | ---- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------ |
| legacy | migrate stores --dry-run | 0    | global: 2 intents, 10 documents, 2 savepoint lines, 2 rulings, and 3 links / would import: 2 intents, 10 documents, 2 savepoint lines, 2 rulings, and 3 links | plastic migrate stores --apply |
| legacy | migrate stores --apply   | 0    | global: 2 intents, 10 documents, 2 savepoint lines, 2 rulings, and 3 links / total: 2 intents, 10 documents, 2 savepoint lines, 2 rulings, and 3 links        | plastic next --project global  |
| none   | migrate stores           | 2    | pass exactly one of --dry-run or --apply                                                                                                                      | none                           |
