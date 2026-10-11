# plastic hook start

SessionStart: name the harness, open the session row, print the state the rows carry.

SessionStart: names the harness, opens the session row with it, then prints the Recap the rows alone carry, and, on a session that starts fresh, one line naming plastic doctor when a doctor check fails or when the harness it recorded is not registered. Nothing here is call memory: a hook keeps no routine run.

```sh
plastic hook start
```

The command is `Start`, in [`start.rb:16`](../../../../scripts/lib/plastic/hooks/start.rb#L16). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

## What it touches

![What plastic hook start touches](component.svg)

## The command

The hook's `respond`, at [`start.rb:30`](../../../../scripts/lib/plastic/hooks/start.rb#L30):

```ruby
def respond(event)
  [*recap(event), doctor_line(event)].compact.join("\n")
end
```

## How the call flows

![The call of plastic hook start](call.svg)

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| answers the event | 0 | prints no next: line | [`start.rb:30`](../../../../scripts/lib/plastic/hooks/start.rb#L30) |
