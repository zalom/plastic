# plastic roadmap new

`plastic roadmap new NAME` creates a roadmap, and `roadmap batch` then writes its batches. `--title` and `--goal` describe the roadmap; the title is the name when `--title` is absent. A name that is taken exits 1 and changes nothing. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup            | call                                                          | exit | result                      | next line                                     |
| ---------------- | ------------------------------------------------------------- | ---- | --------------------------- | --------------------------------------------- |
| none             | roadmap new shop --title Shop --goal "guest checkout is safe" | 0    | roadmap: shop Shop          | plastic roadmap batch shop 1 --project global |
| none             | roadmap new shop                                              | 0    | roadmap: shop shop          | plastic roadmap batch shop 1 --project global |
| roadmap new shop | roadmap new shop                                              | 1    | roadmap shop already exists | plastic roadmap show shop --project global    |
