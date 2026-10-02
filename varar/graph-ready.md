# plastic graph ready

`plastic graph ready ID` lists the nodes ready to claim and offers the first one. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup                                                                                                                                                                        | call          | exit | result                    | next line                                |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------- | ---- | ------------------------- | ---------------------------------------- |
| intent new Alpha ; node add 1 Build --criterion "tests pass" ; node add 1 Test --criterion "suite green" ; edge add 1 n2 n1                                                  | graph ready 1 | 0    | ready: n2 Test            | plastic node claim 1 n2 --project global |
| intent new Alpha ; node add 1 Build --criterion "tests pass" ; node add 1 Test --criterion "suite green" ; edge add 1 n2 n1 ; node claim 1 n2 ; node done 1 n2 --judge tests --findings "Dependency verification passed" | graph ready 1 | 0    | ready: n1 Build           | plastic node claim 1 n1 --project global |
| intent new Alpha | graph ready 1 | 0 | 1. Read the intent's goal and done criteria. Add work with plastic node add 1 TITLE --criterion TEXT, then add dependencies with plastic edge add. Use plastic graph ready 1 after the plan is recorded. | none |
| none                                                                                                                                                                         | graph ready 9 | 1    | no intent 9 in this store | none                                     |
