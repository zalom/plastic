# plastic intent judge

`plastic intent judge ID` takes no options. It prints the steps that start a reasoning judge agent (the harness picks which kind) and tells the judge to record its verdict with `plastic intent verdict ID accept|revise TEXT`. It writes no row. After an accept it says so and offers `plastic intent end`. After two verdicts it is refused as the owner's step. A missing, done or abandoned intent fails. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup                                              | call                            | exit | result                    | next line            |
| -------------------------------------------------- | ------------------------------- | ---- | ------------------------- | -------------------- |
| intent new Alpha ; intent verdict 1 accept "Holds" | intent judge 1                  | 0    | none                      | plastic intent end 1 |
| intent new Alpha                                   | intent judge 1 --verdict accept | 2    | invalid option: --verdict | none                 |
| none                                               | intent judge 9                  | 1    | no intent 9 in this store | none                 |
