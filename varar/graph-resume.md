# plastic graph resume

`plastic graph resume` says where each named store's work stopped and what runs next. It reads the rows and writes nothing. `--stores a,b` names several stores, and a name must be a registered project or global. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead, and `register SLUG` makes a store directory and lists it in projects.yml. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup | call | exit | result | next line |
| ----- | ---- | ---- | ------ | --------- |
| none | graph resume | 0 | store: global / in play: none / then: none (because nothing is open) | plastic status |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- the CLI ships\n" ; sync up ; auto start 1 ; node add 1 Build --criterion "tests pass" | graph resume | 0 | store: global / in play: 1 Alpha (active) / savepoint: TIME Opened: Alpha / then: plastic node claim 1 n1 (because node n1 is ready) | plastic node claim 1 n1 --project global |
| register b ; intent new Alpha | graph resume --stores global,b | 0 | store: global / in play: none / then: none (because nothing is open) / store: b / in play: 1 Alpha (open) / savepoint: TIME Opened: Alpha / then: plastic intent spec 1 (because intent 1 has no done criteria) | plastic intent spec 1 --project b |
| register b | graph resume --stores nope | 2 | no registered project named "nope"; the projects are b | none |
