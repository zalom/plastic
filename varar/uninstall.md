# plastic uninstall

`plastic uninstall` lists the registered harnesses that are found or recorded,
with every recorded one picked, and removes from each picked harness exactly
what its record under `~/.plastic/installations/` lists. The person's own
settings entries stay, and so does the home. With no terminal, it prints the
numbered list and a next line that asks the person; `plastic uninstall ANSWER`
then reads the answer. `--dry-run` lists each file it would remove or change and
changes nothing.
