# Architecture

This page covers the `plastic` command. The system architecture, with the two processes and
the store layout, is in [docs/architecture.md](../architecture.md).

## The life of a command

```text
bin/plastic
  Plastic::CLI.call(ARGV)            the dispatcher
    TABLE[name]                      one frozen hash: name, file, class, help line
    --help? print USAGE_LINE         nothing is built
    Command.call(rest, out:, err:)   builds the command and sends it call
      call                           the work of one command
      flush                          prints the result, or the JSON form
    exit code 0, 1, 2 or 3
```

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

Three SQLite databases sit at the top of the Plastic home: `knowledge_graph.db`,
`work_graph.db` and `references.db`. `plastic sync` builds them from the store files and keeps
them level, `plastic index` rebuilds the search index in `knowledge_graph.db`, `plastic search`
and `plastic query` read that index, `plastic checkout` restores missing store files from the
databases, and `plastic backup` archives them.

## The tri-graph kernel

A second command line sits beside the live one. It is the kernel of the tri-graph design, the
design that moves Plastic's work into three graph databases. The kernel is stage 1 of eight in
that build. It lives under `scripts/lib/plastic/`, and `scripts/lib/plastic.rb` loads it.

The kernel has no command yet. Its command table and its workflow registry are both empty, and
`bin/plastic` does not call it. The live command line described above still serves every
command. Stage 2 adds the first commands and the other two graphs.

The kernel ships in the install manifest, so an installed copy carries it. It defines some of
the same constant names as the live command line, such as the command base class and the
output class. So its tests run in a separate process, as the tests section of the
[technical reference](TECHNICAL.md) describes.

### The kernel's classes

The following table lists the kernel's main classes. Each one sits in the `Plastic` module.

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
| `RoutineRun` | One call of one tool on one subject, kept as a row of the work graph. |
| `Graph::Database` | One SQLite file, reached through the `sqlite3` program. |
| `Hook` | The base class of a hook command. It prints a plain text reply and always exits 0. |

`Plastic.now` is the one source of the time. It gives the local time with its offset.

### The life of a routine call

The following block shows one call of a routine command, from the dispatcher down to the exit
code.

```text
Plastic::CLI.call(argv, environment:)     the kernel's dispatcher
  find the command                         the longest table entry that starts argv
  load its class                           only on the first call
  Command.call(rest, words:, environment:) builds the command and sends it run
    check the scope                        a project named with --project must exist
    Routine#call
      Routine.verify                       once per process; raises every chain fault at once
      open the routine run                 the open row for this tool and subject, or a new one
      build the context                    saved facts first, then this call's arguments
      Traversal#call                       starts at the first workflow of the chain
        run the workflow                   it returns an outcome name or an end value
        follow the edge                    the edge that carries that outcome
        save the routine run               after each workflow, for a tool that writes
        repeat                             until an end value, or until the edge reaches :noop
      close the routine run                the end value names its status and its lines
      report                               the printed lines, then the wrote: line
        the end value prints its lines     next: and because:, or the error line
    flush                                  prints the rows, or one JSON document with --json
  exit code 0, 1 or 3
```

A usage error still exits 2, as it does in the live command line.

### The chain and its four endings

A routine names its chain in its class body. Each `workflow` line gives a key and the edge
that each outcome takes. The special key `:noop` ends the chain.

```text
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

```text
Routine call
  code workflow                     runs its gates, reads and steps in order
    a gate stops as a refusal       Refused     exit 3   the owner holds this step
    a step breaks                   Failed      exit 1   the error names the workflow and step
    a gate stops as a failure       Failed      exit 1   the agent can fix it
    returns an outcome name         follow the edge to the next workflow
  agent workflow                    checks the done test of each step
    steps are left                  HandedOff   exit 0   prints the steps, then next:
                                                exit 1   when the outcome says stops: :failure
    every step is done              the edge reaches :noop, since an agent workflow is last
  the edge reaches :noop            Finished    exit 0   prints next: and because:
```

![A chain of two code workflows and one agent workflow. Refused, Failed, HandedOff and Finished each end the call with their own exit code.](../resources/routine-endings.svg)

`docs/resources/routine_endings.rb` draws the figure. Run it from the repository root after
you change it.

### The routine run row

A routine run is one call of one tool on one subject. A tool that writes keeps it as a row of
the `routine_runs` table in `work_graph.db`, which sits at the top of the Plastic home. The key
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

`Graph::Database` runs one `sqlite3` process for each read or write. A write is one
transaction that takes the write lock first. The first script of a process carries the schema,
so a new home needs no setup step. The report counts the rows a call wrote and prints them on
its `wrote:` line.

### The hook reply

A hook is a command that the harness calls on an event, such as the start of a session. A
hook is not a routine. It prints no `next:` line and keeps no routine run.

```text
the harness sends an event          JSON on stdin
  Hook.call(argv, environment:)
    read the event                  empty input is an empty event
    respond(event)                  the subclass returns text, or nil
    print the text on stdout        only when there is text
  exit 0
  on any error                      one line on stderr, then exit 0
```

Claude Code adds the text to the agent's context on the session start event. A broken hook
never breaks the session, because the hook always exits 0.
