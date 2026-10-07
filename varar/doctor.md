# plastic doctor

`plastic doctor` checks the installation, the databases, the hooks and the instruction files of
the harness it runs in, and names one repair for each finding. It reads files and opens
databases read-only, so it changes nothing.

Each row starts from a home made by Plastic's own commands: `plastic install --claude`, then
`plastic next` and `plastic project new alpha PROJECT`, and an AGENTS.md and a CLAUDE.md in the
project folder. Then the row makes one damage and runs the doctor. The check column names the
row that holds the finding, and the repair column the repair the doctor printed, with PROJECT
for the project folder. Last, the row runs that repair, or makes that file edit, and runs the
doctor again.

Each row gives the damage, the exit code, the check, the repair and the exit code after repair:

| damage                                    | exit | check             | repair                                       | after repair |
| ----------------------------------------- | ---: | ----------------- | -------------------------------------------- | -----------: |
| none                                      |    0 | none              | none                                         |            0 |
| remove references.db from the store       |    1 | store alpha       | plastic project new alpha PROJECT            |            0 |
| drop the intents table from work_graph.db |    1 | store alpha       | plastic project new alpha PROJECT            |            0 |
| remove the machine database               |    1 | machine database  | plastic next                                 |            0 |
| make the launcher not executable          |    1 | hook SessionStart | plastic install --claude --reinstall         |            0 |
| clear the Plastic block from CLAUDE.md    |    1 | CLAUDE.md         | plastic install --claude --reinstall         |            0 |
| clear the project CLAUDE.md               |    1 | CLAUDE.md alpha   | add the line @AGENTS.md to PROJECT/CLAUDE.md |            0 |
