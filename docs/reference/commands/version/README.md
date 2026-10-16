# plastic version

Print the installed Plastic version and release channel.

The version of the package this command came from, its channel and the file it was read from.

```sh
plastic version
```

The command is `Version`, in [`version.rb:9`](../../../../lib/plastic/commands/version.rb#L9). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

## What it touches

![What plastic version touches](component.svg)

## How the call flows

![The chain of workflows that plastic version runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Version](#codeversion) | code | [`version.rb:11`](../../../../lib/plastic/workflows/code/version.rb#L11) |

### Code::Version

The code workflow `:code_show_version`, in [`version.rb:11`](../../../../lib/plastic/workflows/code/version.rb#L11).

Reads the version of the running package: its VERSION file when it has one, as an installed copy does, otherwise its package.json.

![How Code::Version runs: its steps, where it stops, and its outcomes](code_show_version.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| find the version file of the running package | read |  | [`version.rb:16`](../../../../lib/plastic/workflows/code/version.rb#L16) |
| the running package has no VERSION file and no package.json | gate, stops with exit 1 | `!context.source.nil?` | [`version.rb:20`](../../../../lib/plastic/workflows/code/version.rb#L20) |
| say the version and its channel | read |  | [`version.rb:23`](../../../../lib/plastic/workflows/code/version.rb#L23) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic status | [`version.rb:30`](../../../../lib/plastic/workflows/code/version.rb#L30) |

It sets `source`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| the running package has no VERSION file and no package.json | 1 | prints no next: line | [`version.rb:20`](../../../../lib/plastic/workflows/code/version.rb#L20) |
| the command line works, so read the work next | 0 | plastic status | [`version.rb:30`](../../../../lib/plastic/workflows/code/version.rb#L30) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
