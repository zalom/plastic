# plastic status

`plastic status` lists each store with its open and active intents, and counts each intent's nodes by state. With `--project NAME` it lists only that store. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup                                                                                                                                                                  | call   | exit | result                                                           | next line                     |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ | ---- | ---------------------------------------------------------------- | ----------------------------- |
| none                                                                                                                                                                   | status | 0    | store: global                                                    | plastic next --project global |
| intent new Alpha ; intent new Beta                                                                                                                                     | status | 0    | store: global / 1 Alpha (open) no nodes / 2 Beta (open) no nodes | plastic next --project global |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- [tests-pass] the CLI ships\n" ; sync up ; intent approve 1 ; auto 1 ; node add 1 Build --criterion tests-pass | status | 0    | store: global / 1 Alpha (active) open: 1                         | plastic next --project global |
