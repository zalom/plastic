# plastic project new

`plastic project new SLUG PATH` registers a project in projects.yml and leaves its store ready for `plastic intent new`. A name takes lowercase letters, digits and dashes, and `global` is refused. The path must be a folder. A name already registered at another path is refused, and the same name at the same path again changes nothing. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup | call | exit | result | next line |
| ----- | ---- | ---- | ------ | --------- |
| none | project new blog /tmp | 0 | project blog: /tmp | plastic intent new TITLE --project blog |
| project new blog /tmp | project new blog /tmp | 0 | project blog: /tmp | plastic intent new TITLE --project blog |
| none | project new Bad_Name /tmp | 2 | the name must be lowercase letters, digits and dashes | none |
| none | project new global /tmp | 3 | global is the name of the global store, not of a project | none |
| none | project new blog /nowhere | 1 | /nowhere is not a directory | none |
