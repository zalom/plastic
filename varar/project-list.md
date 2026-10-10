# plastic project list

`plastic project list` lists the projects of projects.yml, one project row each with its name and path, and adds `(no store)` when the project's store folder is missing. It writes nothing. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup                 | call         | exit | result             | next line                     |
| --------------------- | ------------ | ---- | ------------------ | ----------------------------- |
| none                  | project list | 0    | none               | plastic project new SLUG PATH |
| project new blog /tmp | project list | 0    | project blog: /tmp | plastic status                |
