# Architecture

This page covers the `plastic` command. The system architecture, with the two processes and
the store layout, is in [docs/architecture.md](../architecture.md).

## The life of a command

`bin/plastic` runs the dispatcher. The dispatcher finds the command in its table, prints the
usage line on `--help` without building anything, or builds the command and sends it `call`
and then `flush`. The call exits 0, 1, 2 or 3.

The dispatcher's table is one frozen hash: the command's name, its file, its class and its
help line. The `call` method does the work of one command, and `flush` prints the result or
its JSON form.

## The shared classes

`CLI` lives in `scripts/lib/cli.rb`; the rest live under `scripts/lib/cli/`.

| Class | Job |
| ----- | --- |
| `CLI` | Finds the command in `TABLE`, answers `--help`, suggests the closest name. |
| `TABLE` | The whole command line in one hash. `plastic help` reads it and loads nothing. |
| `Command` | The base class. Its class method `call` maps errors to exit codes. |
| `Output` | Prints rows, the `next:` and `because:` lines, and the `--json` form. |
| `Scope` | Decides which store a command works on. |
| `Frontier` | Reads what comes next in a scope, for `next` and `continue`. |
| `Legacy` | Runs a script that has no library behind it, and hands back its exit status. |
| `IntentProgress` | Picks the next command for one intent, for `intent show` and `intent step`. |

## Errors and exit codes

A command raises, and the class method `call` maps the error.

| Raised | Exit code |
| ------ | --------- |
| Nothing | 0 |
| `Failure` | 1 |
| `Usage`, `OptionParser::ParseError`, `Scope::UnknownProject` | 2 |
| `Refusal` | 3 |

## Injection

A command receives its streams, environment, home directory and working directory as
arguments. No command reads `ENV`, `Dir.home` or `$stdout` directly, so a test never touches
the real store.

## The three databases

This section describes the kernel's storage. The live command line keeps its own databases at
the top of the home until `bin/plastic` switches to the kernel, a later stage.

Each store keeps its rows in three SQLite databases inside its own folder: `work_graph.db`,
`knowledge_graph.db` and `references.db`. The store folder's `.gitignore` lists them, so they
are never versioned. The files printed from them are. The home keeps one database of its own,
`home.db`, for the routine runs of every store. Its `routine_runs` table is the only table
with a `store` column.

Every row that a store database writes carries `origin_id`, the id of the installation that
wrote it. The id sits in a file at the home and is made on first use. Each store database has
two more tables:

- **`changes`** logs every write: the table, the row key, put or remove, the whole row, the
  time and the origin. The log row is written in the same transaction as the write, so a
  failed write leaves no log row.
- **`printed`** keeps the hash of every file printed from the rows, as of the last print.

An intent row has its own number in `id` and its Luhmann id in `intent_id`. It also has the
Luhmann id of its parent in `parent_id`, an optional `ref` to an intent it follows, and
`origin_id`. Its status is one of six: open, active, parked, future, done or abandoned.

`store/index.json` lists every intent and cluster of the store in Luhmann order. It replaces
`INDEX.md`. It carries no print time, so rows that did not change print the same bytes.

### Sync up and sync down

`plastic intent new` writes an intent's rows and prints its folder in the same call. The two
sync commands keep the files and the rows level after a hand edit. Three hashes decide what
happens to each file: the file on disk, the text printed from the rows now, and the last print
that `printed` records.

The following table lists what each command does with one file.

| The file and its rows | `sync up` | `sync down` |
| --------------------- | --------- | ----------- |
| The file equals its rows. | Records the hash when it is new. | Records the hash when it is new. |
| Only the file changed. | Reads the file into its rows. | Leaves the file. |
| Only the rows changed, or the file is missing. | Leaves the rows. | Prints the file. |
| Both changed. | A conflict. | A conflict. |

A plain sync with a conflict writes nothing, exits 3 and lists every conflict. With
`--overwrite PATH`, the one file at that path takes the side of the command: `sync up` keeps
the file, and `sync down` keeps the rows. `--overwrite` alone does the same for every
conflict. `--merge` applies the one-sided changes, then exits 3 and lists the conflicts left.

A store written before `store/index.json` has an `INDEX.md` instead. `sync up` on such a store
reads `INDEX.md` once, writes its intents and clusters, reads the intent folders, prints the
whole store, and deletes `INDEX.md`. `sync down` fails on such a store until `sync up` has
imported it.

## The tri-graph kernel

A second command line sits beside the live one. It is the kernel of the tri-graph design, the
design that moves Plastic's work into three graph databases. The kernel is stage 1 of eight in
that build. It lives under `scripts/lib/plastic/`, and `scripts/lib/plastic.rb` loads it.

The kernel has three commands, added in stage 2: `intent new`, `sync up` and `sync down`.
`bin/plastic` does not call it yet, so the live command line still serves every command. The
three databases section above describes the storage these commands use.

The kernel ships in the install manifest, so an installed copy carries it. It defines some of
the same constant names as the live command line, such as the command base class and the
output class. So its tests run in a separate process, as the tests section of the
[technical reference](TECHNICAL.md) describes.

### The kernel's classes

![The kernel's classes. CLI looks up TABLE and runs the command class. CLI::Command is the base class; Group, Hook and Routine subclass it. Routine builds a Context, keeps a RoutineRun and runs each workflow key. Workflow finds a key's class through REGISTRY and returns one of the end values Finished, HandedOff, Failed or Refused. CodeWorkflow and AgentWorkflow are its two lanes, and both reach the Graphs through the context.](../resources/kernel-classes.svg)

The following table lists the same classes. Each one sits in the `Plastic` module.

| Class | Job |
| ----- | --- |
| `CLI` | Finds the longest entry in its command table that starts the arguments, and loads that command's class on first use. |
| `CLI::Command` | The base class of every command. It parses the arguments, runs the call, prints, and maps errors to exit codes. |
| `Routine` | A command whose work is a chain of workflows. The chain is written as data in the class body. |
| `Routine::Chain` | The workflow keys in order and the edges between them. It lists every wiring fault at once. |
| `Routine::Traversal` | One pass along a chain. It runs each workflow and follows the edge its outcome takes. |
| `CodeWorkflow` | Ruby steps that run in order: gates, reads and steps. It returns an outcome name. |
| `AgentWorkflow` | Steps in plain words for the agent. It hands off while any step is left undone. |
| `Context` and `Facts` | The named values of one call. A name that no one declared raises at once. |
| `RoutineRun` | One call of one tool on one subject, kept as a row of `home.db`. |
| `Graph::Database` | One SQLite file. Its engine runs each script: the `sqlite3` program, or an engine a test passes in. Each write logs its `changes` row in the same transaction. |
| `Graph::Origin` | The id of this installation, made at the home on first use. |
| `Graph::WorkGraph` | The writes of a command: routine runs, intents, and the files printed after them. |
| `Graph::RetrievalGraph` | The reads of a command, one table at a time. |
| `Graph::IntentWriter` | Checks and writes a new intent: its Luhmann id, its rows and its folder. |
| `Graph::Printer` | Prints files from their rows and records each hash in `printed`. |
| `Graph::Reader` | Reads a file changed by hand back into its rows: `store/index.json` through `IndexFile`, and a file of an intent folder through `IntentFile`. |
| `Graph::Sync` | Compares each file, its rows and its last print, and plans and applies a sync. |
| `Graph::Sync::Resolution` | Holds how one sync settles a conflict: `--overwrite PATH`, `--overwrite` alone, or `--merge`. |
| `Graph::LuhmannId` | Splits, sorts and extends Luhmann ids, such as the next child of `307a`. |
| `Graph::LegacyIndex` | Reads the `INDEX.md` of a store written before `store/index.json`. |
| `Hook` | The base class of a hook command. It prints a plain text reply and always exits 0. |

`Plastic.now` is the one source of the time. It gives the local time with its offset.

### The life of a routine call

![One call of plastic intent end 12 --as delivered, top to bottom. The kernel opens the databases and picks up the routine run. Find the intent has one gate, intent 12 exists, which fails with exit 1. Check the write lock reads the lock and has two gates that refuse with exit 3. Check the ending has three gates and two outcomes, written and missing. On written, Close the intent runs three steps and finishes with exit 0. On missing, Write the outcome hands off to the agent with exit 0, and the next call finishes once the outcome is recorded.](../resources/routine-call.svg)

The figure shows the shape of every routine call: the kernel opens the databases and the
routine run, each workflow runs its gates, reads, steps and outcomes in order, and the call
ends in one of the four values below. The command it draws, `intent end`, lands in a later stage.

A usage error still exits 2, as it does in the live command line.

### The chain and its four endings

A routine names its chain in its class body. Each `workflow` line gives a key and the edge
that each outcome takes. The special key `:noop` ends the chain.

```ruby
workflow :code_check_write_lock, next: :code_check_ending
workflow :code_check_ending do
  on :written, next: :code_close_intent
  on :missing, next: :agent_write_outcome
end
```

`Routine.verify` checks the chain once per process, before the first workflow runs. It raises
one error that lists every fault, so a reordered chain never skips a workflow in silence. It
finds these faults:

- An edge points backward, or to a key that is not in the chain.
- No edge reaches a workflow.
- An outcome has no edge, or an edge names an outcome the workflow never returns.
- An agent workflow is not the last workflow of the chain.
- An outcome ends the chain, and no outcome line gives its `because:` line.
- A printed line names a fact that no one declares.

A call ends in one of four values. Each value prints its own last lines and gives the exit
code, so no workflow picks a number.

![Above, the chain of the intent end routine: FindIntent, CheckWriteLock and CheckEnding, which ends on written to CloseIntent or on missing to WriteOutcome, an agent workflow, and then :noop, where the report prints next: and because: from the last workflow. Below, inside one code workflow: read runs on every call and changes nothing on disk; step runs while done: is false and changes state; gate stops the whole call unless pass: holds, as Refused with exit 3 or Failed with exit 1; outcome is the first if: that holds.](../resources/routine-chain.svg)

### The routine run row

A routine run is one call of one tool on one subject. A tool that writes keeps it as a row of
the `routine_runs` table in `home.db`, which sits at the top of the Plastic home. The key
is the store, the tool and the subject. A tool that writes nothing keeps its routine run in
memory only.

The traversal saves the row after each workflow, and again when the call ends. The row holds
the facts the call found, the workflows that finished, the workflow it stopped at, and the
lines it printed last.

The following table lists the status values of a routine run.

| Status | What it means | What the next call does |
| ------ | ------------- | ----------------------- |
| `running` | The process is inside the chain, or it died there. | Starts again at the first workflow. |
| `handed_off` | The agent has steps to do. | Reads the saved facts and checks the steps again. |
| `failed` | A step broke. | Retries the workflow that broke. |
| `refused` | The owner holds a step. | Asks again. |
| `finished` | The chain ended. | Starts a new routine run. |

An open routine run restarts at the first workflow with its saved facts. A step that changes
state has a done check, so a change that already happened is skipped and never runs twice.

`Graph::Database` hands each read or write to its engine. The default engine,
`Graph::Database::Program`, runs one `sqlite3` process for each script. A write is one
transaction that takes the write lock first. The first script of a process carries the schema,
so a new home or store needs no setup step. The report counts the rows a call wrote and prints them on
its `wrote:` line.

### The hook reply

A hook is a command that the harness calls on an event, such as the start of a session. A
hook is not a routine. It prints no `next:` line and keeps no routine run.

![What the harness fires and what Plastic does. Session start, once when the session opens and again after a compaction, runs plastic hook continue, which prints the open intents of this store, the locks this session holds and today's hand-off lines. End of the turn runs plastic hook record, which renews the live locks of this session. Prompt sent, before a tool runs, after a tool ran, before a compaction and session end run nothing. A third column names the hooks the proposal had and why each one goes.](../resources/hook-events.svg)

A hook call reads the event as JSON on stdin, hands it to the subclass, prints the returned
text on stdout when there is any, and exits 0. On any error it prints one line on stderr and
still exits 0.

Claude Code adds the text to the agent's context on the session start event. A broken hook
never breaks the session, because the hook always exits 0.
