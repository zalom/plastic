# plastic init

Find the installed harnesses and install Plastic into the ones the person picks.

Finds the installed harnesses, shows them on the choice screen with every found one picked, and installs Plastic into each one the person picks. See docs/help/choice-screen.md.

```sh
plastic init [ANSWER]
```

The command is `Init`, in [`init.rb:12`](../../../../lib/plastic/commands/init.rb#L12). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `ANSWER` | the person's answer to the numbered list | |

## What it touches

![What plastic init touches](component.svg)

## Before the chain

The command's own `call`, at [`harness_pick.rb:12`](../../../../lib/plastic/commands/harness_pick.rb#L12), runs first:

```ruby
def call
  answer = parsed[:answer] ||= answered_on_screen
  super if answer
end
```

## How the call flows

![The chain of workflows that plastic init runs](chain.svg)

| Workflow | Kind | Code |
| --- | --- | --- |
| [Code::Init::Choose](#codeinitchoose) | code | [`choose.rb:14`](../../../../lib/plastic/workflows/code/init/choose.rb#L14) |
| [Code::Init](#codeinit) | code | [`init.rb:13`](../../../../lib/plastic/workflows/code/init.rb#L13) |

### Code::Init::Choose

The code workflow `:code_choose_harnesses`, in [`choose.rb:14`](../../../../lib/plastic/workflows/code/init/choose.rb#L14).

Reads the person's answer against the installed harnesses, every one of them picked at the start.

![How Code::Init::Choose runs: its steps, where it stops, and its outcomes](code_choose_harnesses.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| find the installed harnesses and read the person's answer | read |  | [`choose.rb:19`](../../../../lib/plastic/workflows/code/init/choose.rb#L19) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:none` | when `context.found.empty?` | finishes, exit 0; next: plastic init | [`choose.rb:28`](../../../../lib/plastic/workflows/code/init/choose.rb#L28) |
| `:left` | when `context.picked.empty?` | finishes, exit 0; next: plastic init | [`choose.rb:30`](../../../../lib/plastic/workflows/code/init/choose.rb#L30) |
| `:chosen` | otherwise | runs [Code::Init](#codeinit) | [`choose.rb:32`](../../../../lib/plastic/workflows/code/init/choose.rb#L32) |

It sets `found`, `picked`, `harnesses`.

### Code::Init

The code workflow `:code_install_harnesses`, in [`init.rb:13`](../../../../lib/plastic/workflows/code/init.rb#L13).

Checks the machine, copies the core files on a home that has none, and installs Plastic into each picked harness.

![How Code::Init runs: its steps, where it stops, and its outcomes](code_install_harnesses.svg)

| Step | Kind | Check | Code |
| --- | --- | --- | --- |
| check this machine and the harness settings files | read |  | [`init.rb:18`](../../../../lib/plastic/workflows/code/init.rb#L18) |
| this machine cannot run Plastic; see above | gate, stops with exit 1 | `context.usable` | [`init.rb:25`](../../../../lib/plastic/workflows/code/init.rb#L25) |
| %{broken} is not valid JSON; nothing was changed. Fix the file and run this again | gate, stops with exit 1 | `context.broken.nil?` | [`init.rb:26`](../../../../lib/plastic/workflows/code/init.rb#L26) |
| install Plastic into the picked harnesses | step | `!context.installed.nil?` | [`init.rb:29`](../../../../lib/plastic/workflows/code/init.rb#L29) |

| Outcome | When | Then | Code |
| --- | --- | --- | --- |
| `:done` | always | finishes, exit 0; next: plastic doctor --harness %{checked} | [`init.rb:37`](../../../../lib/plastic/workflows/code/init.rb#L37) |

It sets `usable`, `broken`, `installed`, `checked`.

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| no registered harness was found: no settings folder in the home and no program on the PATH; install one, then run this again | 0 | plastic init | [`choose.rb:28`](../../../../lib/plastic/workflows/code/init/choose.rb#L28) |
| the person left with no change | 0 | plastic init | [`choose.rb:30`](../../../../lib/plastic/workflows/code/init/choose.rb#L30) |
| this machine cannot run Plastic; see above | 1 | prints no next: line | [`init.rb:25`](../../../../lib/plastic/workflows/code/init.rb#L25) |
| %{broken} is not valid JSON; nothing was changed. Fix the file and run this again | 1 | prints no next: line | [`init.rb:26`](../../../../lib/plastic/workflows/code/init.rb#L26) |
| Plastic %{installed} is installed into %{harnesses} | 0 | plastic doctor --harness %{checked} | [`init.rb:37`](../../../../lib/plastic/workflows/code/init.rb#L37) |
| a step raises | 1 | prints no next: line | [`code_workflow.rb:102`](../../../../lib/plastic/code_workflow.rb#L102) |
