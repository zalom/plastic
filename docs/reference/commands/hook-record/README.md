# plastic hook record

Stop: stamp the turn, renew locks, run the stop gate.

```sh
plastic hook record [--harness NAME]
```

The command is `Record`, in [`record.rb:13`](../../../../scripts/lib/plastic/hooks/record.rb#L13). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `--harness NAME` | the harness calling this hook | `"claude-code"` |

## What it touches

![What plastic hook record touches](component.svg)

## The command

The hook's `respond`, at [`record.rb:16`](../../../../scripts/lib/plastic/hooks/record.rb#L16):

```ruby
def respond(event)
  return no_session unless session_id

  stop(event)
end
```

## How the call flows

![The call of plastic hook record](call.svg)

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| answers the event | 0 | prints no next: line | [`record.rb:16`](../../../../scripts/lib/plastic/hooks/record.rb#L16) |
| blocks the stop | 0 | prints no next: line | [`stop_gate.rb:24`](../../../../scripts/lib/plastic/hooks/stop_gate.rb#L24) |
