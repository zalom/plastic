# plastic auto

`plastic auto ID` delivers one intent or one roadmap in auto mode. For an intent id it takes the delivery lock for the session and sets the intent active. It refuses an intent with no done criterion, an open decision or no go-ahead, because those are owner steps. For a roadmap slug it arms the first item in flight, or offers `plastic roadmap start` for a ready item. When the store's project names a repository, it prints the code worktree path and branch as rows, and the agent makes that worktree. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead, and `register SLUG` lists the store in projects.yml with the home as its repository. HOME stands for the home folder.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup | call | exit | result | next line |
| ----- | ---- | ---- | ------ | --------- |
| intent new Alpha | auto 1 | 3 | intent 1 names no done criterion | none |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- the CLI ships\n\n## Open Questions\n\n- which store wins\n" ; sync up | auto 1 | 3 | intent 1 has an open decision; run plastic intent spec 1 | none |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- the CLI ships\n" ; sync up | auto 1 | 3 | intent 1 has no go-ahead; the owner approves it with plastic intent approve 1 | none |
| intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- the CLI ships\n" ; sync up ; intent approve 1 ; auto 1 | auto 1 | 0 | none | plastic intent brief 1 --project global |
| register global ; intent new Alpha ; write store/1--alpha/spec.md "# Spec\n\n## Done criteria\n\n- the CLI ships\n" ; sync up ; intent approve 1 | auto 1 | 0 | worktree: HOME/.claude/worktrees/1--alpha / branch: plastic/1--alpha | plastic intent brief 1 --project global |
| intent new Alpha ; intent new Beta | auto 1 2 | 2 | unexpected 2 | none |
| none | auto 9 | 1 | no intent 9 in this store | none |
| none | auto r9 | 1 | no roadmap r9 | none |
