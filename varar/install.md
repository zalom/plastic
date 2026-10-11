# plastic install

`plastic install` copies the core files of the running package into the home
and makes the global store. On a home that already has them it refuses and
names `plastic init`, which installs Plastic into a harness. `--reinstall`
copies the files again and syncs every harness Plastic is installed into.
`--dry-run` lists each file it would add or replace and changes nothing.
