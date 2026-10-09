# plastic intent note

`plastic intent note ID TEXT` adds one line under `## Notes` in the intent's outcome.md. `--kind` names the line: Review, Commit or Report, and Report is the default. The earlier text stays as an earlier revision of the file. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup            | call                                         | exit | result                       | next line |
| ---------------- | -------------------------------------------- | ---- | ---------------------------- | --------- |
| intent new Alpha | `intent note 1 "all checks pass"`            | 0    | report: all checks pass      | none      |
| intent new Alpha | `intent note 1 "abc123 proves it" --kind Commit` | 0    | commit: abc123 proves it     | none      |
| intent new Alpha | `intent note 1 "text" --kind Typo`           | 2    | KIND takes Review, Commit, Report | none |
| none             | `intent note 9 "text"`                       | 1    | no intent 9 in this store    | none      |
