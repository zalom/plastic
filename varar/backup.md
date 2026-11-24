# plastic store backup

`plastic store backup --project SLUG` copies the databases of one store into a folder named for the UTC time, `stores/SLUG/backups/STAMP/`, and writes one row for it. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `register SLUG` lists a store in `projects.yml`. STAMP stands for the 14-digit UTC folder name and SIZE for a byte count.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup                                           | call                                     | exit | result                                      | next line                          |
| ----------------------------------------------- | ---------------------------------------- | ---- | ------------------------------------------- | ---------------------------------- |
| register alpha ; intent new Alpha --project alpha | store backup --project alpha                     | 0    | backup: alpha/STAMP, 2 databases, SIZE bytes | plastic store backup list --project alpha  |
| register alpha ; intent new Alpha --project alpha | store backup --project alpha --databases work_graph | 0    | backup: alpha/STAMP, 1 database, SIZE bytes | plastic store backup list --project alpha  |
