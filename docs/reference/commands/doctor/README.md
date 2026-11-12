# plastic doctor

Check the installation, the databases and the hooks of this harness, and name each repair.

```sh
plastic doctor [--harness NAME]
```

The command is `Doctor`, in [`doctor.rb:7`](../../../../lib/plastic/commands/doctor.rb#L7). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `--harness NAME` | the harness to check, such as claude-code; the one the call runs in when left out |  |

## What it touches

![What plastic doctor touches](component.svg)

## How the call flows

![The chain of workflows that plastic doctor runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Doctor](#codedoctor) | code | [`doctor.rb:12`](../../../../lib/plastic/workflows/code/doctor.rb#L12) |

### Code::Doctor

The code workflow `:code_check_health`, in [`doctor.rb:12`](../../../../lib/plastic/workflows/code/doctor.rb#L12).

Runs the checks of the shared parts and of one harness, prints a row for each, and names each repair once. It reads files and changes none.

![How Code::Doctor runs: its steps, where it stops, and its outcomes](code_check_health.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| check the installation, the databases, the hooks and the instruction files of the harness | read |  | [`doctor.rb:17`](../../../../lib/plastic/workflows/code/doctor.rb#L17) |
| a check found a problem; run the repairs named above, then run plastic doctor again | gate, stops with exit 1 | `context.repairs.zero?` | [`doctor.rb:25`](../../../../lib/plastic/workflows/code/doctor.rb#L25) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic status | [`doctor.rb:28`](../../../../lib/plastic/workflows/code/doctor.rb#L28) |

It sets `repairs`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| a check found a problem; run the repairs named above, then run plastic doctor again | 1 | prints no next: line | [`doctor.rb:25`](../../../../lib/plastic/workflows/code/doctor.rb#L25) |
| every check passed, so read the work next | 0 | plastic status | [`doctor.rb:28`](../../../../lib/plastic/workflows/code/doctor.rb#L28) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
