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
