# Update safety by harness

A migrated installation must reject packages that cannot read its stores.
Each scenario uses an isolated home and the packaged CLI. The release list
is a fixed local file, read through the same URL override the command honors.
Refusal happens before any install step runs, and must preserve
registration files, version history, and the installed version.

Each row gives the harness, command, exit, installation, and version:

| harness | command | exit | installation | version |
| --- | --- | --- | --- | --- |
| claude | update | 3 | unchanged | unchanged |
| codex | update | 3 | unchanged | unchanged |
| claude | rollback | 3 | unchanged | unchanged |
| codex | rollback | 3 | unchanged | unchanged |
