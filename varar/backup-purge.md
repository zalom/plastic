# plastic backup purge

`plastic backup purge --store SLUG (--older-than DATE | --all | --failed)` deletes backup folders of one store, with their rows, and `--dry-run` previews it. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `register SLUG` lists a store in `projects.yml`. STAMP stands for the 14-digit UTC folder name.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup | call | exit | result | next line |
| ----- | ---- | ---- | ------ | --------- |
| register alpha ; intent new Alpha --project alpha ; backup --store alpha | backup purge --store alpha --all | 0 | purged: alpha/STAMP | plastic backup list --store alpha |
| register alpha ; intent new Alpha --project alpha ; backup --store alpha | backup purge --store alpha --all --dry-run | 0 | preview: purge alpha/STAMP / preview: the original store was not changed | plastic backup purge --store alpha |
| register alpha ; intent new Alpha --project alpha ; backup --store alpha | backup purge --store alpha --older-than 2000-01-01 | 0 | purged: nothing | plastic backup list --store alpha |
| register alpha ; intent new Alpha --project alpha ; backup --store alpha | backup purge --store alpha --failed | 0 | purged: nothing | plastic backup list --store alpha |
