# plastic backup

`plastic backup` packs every database of the home into one archive. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup            | call   | exit | result                                                | next line           |
| ---------------- | ------ | ---- | ----------------------------------------------------- | ------------------- |
| none             | backup | 0    | backup: plastic-STAMP.tar.gz, 1 database, SIZE bytes  | plastic backup list |
| intent new Alpha | backup | 0    | backup: plastic-STAMP.tar.gz, 4 databases, SIZE bytes | plastic backup list |
