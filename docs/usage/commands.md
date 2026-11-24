# The commands by task

This page lists the commands by task. [The command reference](../reference/commands/README.md) has one page for each, and `plastic help` prints the same list in the terminal.

## Orientation
```bash
plastic status                        # Active work in every store
plastic graph resume                  # Where this project's work stopped and what runs next
plastic graph resume --stores blog,shop  # The same, for several named projects
plastic next                          # The next action in one line
```

## Intents
```bash
plastic intent new "TITLE"            # Create a future intent
plastic intent new "TITLE" --parent 12  # Create a branch of intent 12
plastic intent start 12               # Set it in progress for guided work and print the code worktree
plastic intent park 12 "TEXT"         # Park started work with the reason it waits
plastic intent grant 12 "TEXT" --owner  # Grant one extra review round, on the owner's word, once the rounds are used
plastic intent show 12                # Print the state screen
plastic intent spec 12                # State screen, then the speccing rules
plastic intent rule 12 "TEXT"         # Record a ruling, as a row and a work log line
plastic intent revise 12 "LINE" --why "TEXT"  # Rewrite the What and the Why, keeping the old text
plastic intent note 12 "TEXT"                     # Add a line under Notes in outcome.md; --kind Review, Commit or Report
plastic session note "TEXT"           # Write the one prose line of this session
plastic intent link 12 cites 7        # Link intent 12 to intent 7
plastic intent unlink 12 cites 7 --dry-run   # Preview the removal of a link
plastic intent archive 12 --dry-run   # Preview an archive
plastic intent archive --older-than 2026-01-01   # Archive each intent older than the date
plastic intent unarchive 12             # Restore an archived intent
plastic intent end 12                   # Close as delivered, after the merge; it also releases the driver claim
plastic intent abandon 12               # Close as abandoned
```

## Graphs and needs links
```bash
plastic graph show 12                 # The work graph of intent 12
plastic graph ready 12                # The nodes ready to start
plastic graph check 12                # Find a done node with no findings, an isolated node, a retry cap, a loop or a stray schema file
plastic node claim 12 n3 --agent NAME  # Claim a ready node
plastic node done 12 n3 "TEXT"        # Close a claimed node with its findings
plastic node resolve 12 n3 "TEXT"     # Reopen a node that needs info or is impeded
plastic node remove 12 n3 --dry-run   # Preview a node removal
plastic edge remove 12 n2 n3 --dry-run   # Preview an edge removal
plastic intent link 12 needs 7       # Intent 12 waits for intent 7
```

A `--dry-run` call runs in a disposable copy of the store. It prints what it would
write, never touches the original, and ends with the same call without `--dry-run`.

## Auto teams
```bash
plastic intent auto 12                 # Set the intent in progress for agent delivery and print the code worktree
plastic intent brief 12                # Print the brief an agent starts from
```

## Console
```bash
plastic console                              # IRB over the store databases, opened read-only
plastic console --project NAME -e 'knowledge.execute("SELECT title FROM intents")'  # One piece of Ruby: print its value and exit
plastic console -e 'work.execute("SELECT count(*) AS n FROM nodes")' --json  # The value as JSON data
```

The names are `work`, `knowledge`, `retrieval` and `plastic`: the three files of the store and
`plastic.db`. The console is no sandbox: Ruby can still write files. IRB is the one of the Ruby
installation; when the Ruby has none, add it with `gem install irb`. See the
[page of `console`](../reference/commands/console/README.md).

## Search
```bash
plastic search recovery flow --source-project blog --limit 20  # Ranked passages for the words of a question; quote a phrase to keep it whole
plastic document get REFERENCE --json                           # One immutable document
plastic document batch REFERENCE... --json                      # Documents in request order
plastic intent discover 12 recovery flow                         # Save candidate provenance
plastic intent context 12 --from selected-context.json           # Save agent-selected context
plastic architecture status --project blog                       # Tell the agent to check the architecture map
plastic architecture refresh --project blog                      # Tell the agent to regenerate the map
```

## Stores and databases
```bash
plastic store sync up                       # Bring the databases level with the store files; an intent folder with no rows gets its rows back
plastic project list                  # The registered projects with their paths
plastic project load blog shop        # A short digest of each project: paths, files to read, work in play with its passages, last deliveries
plastic project new blog ~/code/blog  # Register a project and leave its store ready for intent new
plastic project links                 # List the links that name an intent or a ruling this store lacks
plastic store sync up --dry-run             # Show what would change
plastic store sync down                     # Write the store files from the databases
plastic store backup --project blog          # Copy the databases of one store (or --project global) into a UTC-named folder
plastic store backup --project blog --live   # The same, printing each line of backup.log as it is written
plastic store backup list --project blog     # Folder, start time, status and goal of each backup
plastic store backup purge --project blog --older-than 2026-09-01   # Delete older backups
plastic store backup purge --project blog --failed   # Delete the backups that failed
plastic store backup restore --project blog --latest   # Put the newest done backup back; it ends by asking whether to sync up or down
plastic store migration list --project blog  # The store's version, its kept rows, its ledger, and what a down would undo
plastic store migration down --project blog  # Put back the rows the newest migration kept in legacy.db, after a backup
plastic store migration purge 20261119000000 --project blog   # Remove the rows one migration kept, so it can no longer be undone
```

## Product
```bash
plastic init                          # Install into the agents you pick
plastic install --reinstall           # Copy the files again and sync every agent
plastic update                        # The newest stable release
plastic rollback                      # Switch back to the previous release
plastic uninstall                     # Remove Plastic from the agents you pick. Your stores stay.
plastic version                       # The installed version and its channel
plastic doctor                        # The installation, the databases and the hooks of this agent
```

## Help
```bash
plastic help                          # All commands, grouped in families
plastic help intent                   # The commands of one family
plastic help intent end               # The usage line of one command
plastic help tools                    # One help topic
```

## Global options

```bash
--json          # Print the result as data with stable keys
-h, --help      # Print the usage line of the command
--project SLUG  # Name a project other than the one the working directory is in
```

The installer commands and `plastic hook EVENT` do not take `--json`.

## Agent hooks

The installer registers hooks in your agent. At session start a hook loads the conventions
and prints where the work stands, and `hook prompt` records each prompt in the machine's chat history.
When a session stops or ends, a hook records it. Each hook
calls the active release launcher under `~/.local/share/plastic`:

```bash
plastic hook start      # SessionStart; the agent calls these, not you
plastic hook prompt     # UserPromptSubmit
plastic hook stop       # Stop
plastic hook end        # SessionEnd
```

The start hook names the harness that runs the session and records it on the session row.
The other hooks and commands read it from there.

Run `plastic doctor` when hooks do not fire. Use `--harness codex` or
`--harness claude-code` to choose the installation to check. Codex runs a hook only after
you trust it in `/hooks`, and the installer names each hook that changed. The doctor names
each repair, such as `plastic install --reinstall`.

## Configuration

`plastic config list` prints every setting, `plastic config set KEY VALUE` writes one, and
`~/.plastic/config.yml` is printed from them. [The features page](FEATURES.md#settings) says what
each setting does, and the [page of `config`](../reference/commands/config/README.md) lists the keys.
