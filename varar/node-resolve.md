# plastic node resolve

`plastic node resolve ID NODE TEXT` reopens a needs_info or impeded node with its resolution. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead. TIME stands for a timestamp.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup | call | exit | result | next line |
| --- | --- | --- | --- | --- |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- [tests-pass] tests pass\n" ; sync up ; node add 1 Build --criterion tests-pass ; node claim 1 n1 ; node ask 1 n1 "which harness" | node resolve 1 n1 "Claude Code" | 0 | node: n1 open | plastic node claim 1 n1 --project global |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- [tests-pass] tests pass\n" ; sync up ; node add 1 Build --criterion tests-pass ; node claim 1 n1 ; node impede 1 n1 "no access" | node resolve 1 n1 "access granted" | 0 | node: n1 open | plastic node claim 1 n1 --project global |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- [tests-pass] tests pass\n" ; sync up ; node add 1 Build --criterion tests-pass | node resolve 1 n1 "Claude Code" | 1 | node n1 is open; it cannot move to open | none |
