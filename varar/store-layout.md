# Store layout by harness

Each row installs the npm archive into an isolated home, registers the chosen
harness, creates a project, and creates an intent through the public CLI.
Legacy rows first seed a store, then migrate it with the public command and
verify its retained backup. No scenario uses agent credentials or model calls.
These rows cover layout and registration. Full doctor and live agent delivery
remain separate acceptance checks; the public doctor currently defaults to Claude.

Each row gives the harness, starting layout, global store, project intent, registered harness, legacy directory, backup, and repeated migration exit:

| harness | starting layout | global store | project intent | registered harness | legacy directory | backup | repeated migration exit |
| --- | --- | --- | --- | --- | --- | --- | --- |
| claude | fresh | present | present | present | absent | absent | not run |
| codex | fresh | present | present | present | absent | absent | not run |
| claude | legacy | present | present | present | absent | preserved | 3 |
| codex | legacy | present | present | present | absent | preserved | 3 |
