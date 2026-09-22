# Architecture

This page covers the `plastic` command. The system architecture, with the two processes and
the store layout, is in [docs/architecture.md](../architecture.md). That page moves into this
slot when the scripts and tests that name its path change, in intent 372.

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

All of them live under `scripts/lib/cli/`.

| Class | Job |
| ----- | --- |
| `CLI` | Finds the command in `TABLE`, answers `--help`, suggests the closest name. |
| `TABLE` | The whole command line in one hash. `plastic help` reads it and loads nothing. |
| `Command` | The base class. Its class method `call` maps errors to exit codes. |
| `Output` | Prints rows, the `next:` and `because:` lines, and the `--json` form. |
| `Scope` | Decides which store a command works on. |
| `Frontier` | Reads what comes next in a scope, for `next` and `continue`. |
| `Legacy` | Runs a script that has no library behind it, and hands back its exit status. |

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

## The three graphs

The knowledge graph, the work graph and the retrieval graph each get a home on disk and a
command family. This batch ships the foundation only. Batch 3 of the roadmap adds the
databases and the retrieval commands, and this page gains their sections then.
