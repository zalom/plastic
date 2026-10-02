# plastic backup list

`plastic backup list` lists the archives `plastic backup` made, and fails when one is missing or changed. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup  | call        | exit | result                                         | next line      |
| ------ | ----------- | ---- | ---------------------------------------------- | -------------- |
| none   | backup list | 0    | no backups                                     | plastic backup |
| backup | backup list | 0    | backup: plastic-STAMP.tar.gz, SIZE bytes, TIME | plastic backup |
