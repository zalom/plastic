# plastic project new

Register a project and leave its store ready for intent new.

Registers a project in projects.yml and leaves its store ready, so an intent can be opened at once. The other lines of the file stay as they are. The same name at the same path again changes nothing.

```sh
plastic project new SLUG PATH
```

The command is `Project::New`, in [`new.rb:14`](../../../../lib/plastic/commands/project/new.rb#L14). The words on this page, such as gate, step and outcome, are explained in [the command DSL](../../dsl/README.md).

| Argument or option | What it gives | Default |
| --- | --- | --- |
| `SLUG` | the project's name: lowercase letters, digits and dashes | |
| `PATH` | the project's repository folder | |

## What it touches

![What plastic project new touches](component.svg)

## The command

The command's `call`, at [`new.rb:19`](../../../../lib/plastic/commands/project/new.rb#L19):

```ruby
def call
  slug = checked_slug
  path = checked_path
  register(slug, path)
  make_ready(slug)
  announce(slug, path)
end
```

## How the call flows

![The call of plastic project new](call.svg)

## Outcomes

Every call can also end in [the ways any call can end](../../dsl/README.md#how-any-call-can-end).

| Ending | Exit | next: | Code |
| --- | --- | --- | --- |
| Failed: %{path} is not a directory | 1 | prints no next: line | [`new.rb:33`](../../../../lib/plastic/commands/project/new.rb#L33) |
| Refused: %{slug} is registered at %{known}, not at %{path}; edit projects.yml to move it | 3 | prints no next: line | [`new.rb:41`](../../../../lib/plastic/commands/project/new.rb#L41) |
| Offers the next command | 0 | plastic intent new TITLE --project SLUG | [`new.rb:52`](../../../../lib/plastic/commands/project/new.rb#L52) |
