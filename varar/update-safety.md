# Update safety by harness

A migrated installation must reject packages that cannot read its stores.
Each scenario uses an isolated home and the packaged CLI. Registry responses
are fixed, and the installer subprocess is disabled. Refusal must preserve
registration files, version history, and the installed version.

Each row gives the harness, command, exit, installation, and version:

| harness | command | exit | installation | version |
| --- | --- | --- | --- | --- |
| claude | update | 3 | unchanged | unchanged |
| codex | update | 3 | unchanged | unchanged |
| claude | rollback | 3 | unchanged | unchanged |
| codex | rollback | 3 | unchanged | unchanged |
