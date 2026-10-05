# plastic backup list

`plastic backup list --store SLUG` lists the backup folders of one store with their status and goal, and fails when a backup with a row is missing or changed. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `register SLUG` lists a store in `projects.yml`. STAMP stands for the 14-digit UTC folder name.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup                                                                | call                      | exit | result                                  | next line                     |
| -------------------------------------------------------------------- | ------------------------- | ---- | --------------------------------------- | ----------------------------- |
| register alpha                                                       | backup list --store alpha | 0    | no backups                              | plastic backup --store alpha  |
| register alpha ; intent new Alpha --project alpha ; backup --store alpha | backup list --store alpha | 0    | 1 STAMP TIME done full                  | plastic backup --store alpha  |
