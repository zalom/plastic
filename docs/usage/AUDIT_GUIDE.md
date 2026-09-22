# Audit guide

An audit answers one question: does the record on disk say what happened?

Plastic keeps its record in plain files, so you can audit it with a pager and Git.
[Reading the ledgers](../guides/reading-the-ledgers.md) explains each ledger and how to read
it by hand. [Reading a delivered intent](../guides/reading-a-delivered-intent.md) covers one
finished intent.

## Audit the command line

| Question | Command |
| -------- | ------- |
| Which version is installed, and from which file was it read? | `plastic version` |
| Which versions has this machine run? | `plastic rollback --list` |
| What is active in every store? | `plastic status --json` |
| Why is this the next action? | `plastic next --why` |
