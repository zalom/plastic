# plastic intent abandon

`plastic intent abandon ID` closes an intent that will never ship. It takes no options. outcome.md says why the intent is dropped and records `- Reverted: WHAT` under `## Verification`. Without the Reverted line the command hands the agent the revert steps, exit 0, and changes nothing. Plastic runs no version control command; the agent undoes the changes and records them.

With the line, the intent ends as abandoned with no completion record, and the delivery lock is released. Its disposition is `superseded` when a `supersedes` link from another intent points at it, and `cancelled` otherwise. A done or abandoned intent fails. A live lock of another session refuses with exit 3. The rows below run the storage kernel's command line in a fresh home each time, as session s-1. A setup lists the calls made first, in order, split by a semicolon; `write PATH TEXT` writes a file in the store instead.

Each row gives the setup, the call, the exit code, the result and the next line:

| setup | call | exit | result | next line |
| ----- | ---- | ---- | ------ | --------- |
| intent new Alpha ; write store/1--alpha/outcome.md "# Outcome\nDropped.\n\n## Verification\n- Reverted: nothing delivered\n" ; sync up | intent abandon 1 | 0 | intent: 1 abandoned / 1. Stop the processes and the agents that intent 1 started: servers, watchers, background jobs and subagents. Plastic runs none of them and stops none of them. | none |
| intent new Alpha ; write store/1--alpha/outcome.md "# Outcome\nDropped.\n" ; sync up | intent abandon 1 | 0 | 1. Undo what intent 1 changed with your own version control tool: close or delete its branch and worktree, and revert any commit that reached the base. Plastic runs no version control command; it records what you write. / 2. Write in store/1--alpha/outcome.md why the intent is dropped, and add the line '- Reverted: <what was undone, or nothing delivered>' under ## Verification. Run plastic sync up and then plastic intent abandon 1 again. | none |
| intent new Alpha ; write store/1--alpha/outcome.md "# Outcome\nDropped.\n\n## Verification\n- Reverted: nothing delivered\n" ; sync up ; intent abandon 1 | intent abandon 1 | 1 | intent 1 is abandoned; it can no longer be abandoned | none |
| intent new Alpha | intent abandon 1 --judge agent | 2 | invalid option: --judge | none |
| none | intent abandon 9 | 1 | no intent 9 in this store | none |
