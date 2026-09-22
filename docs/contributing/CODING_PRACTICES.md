# Coding practices

The aim is simple code that is easy to change.

## Commands

- A class that does one job has a public `call`, and a class method `call` that runs
  `new(...).call`. Never name it `run`.
- In a base class, `call` raises `NoMethodError` with the class name. Nothing runs before it:
  no parsing, no setup.
- A hook that the base class calls on itself is private. In the base class it raises
  `NoMethodError`. Never use `NotImplementedError`, which Ruby reserves for a feature the
  platform lacks, and never `protected`.
- Each command class defines its own `USAGE_LINE` constant.
- Options are parsed on the first read of `options`, not in `initialize`.

## Code

- The run time uses the Ruby standard library only. New gems are development gems.
- Inject streams, the environment and paths. Never reach for a global in a command.
- Call existing library code in the same process. Never copy it.
- Code carries no comments beyond the file header that states the contract.
- Scripts run under Ruby 4.0 or later. Shell scripts run under bash 3.2.

## Lint

RuboCop runs with the Standard configuration as its base, plus `rubocop-minitest`.
`.rubocop.yml` is for the editor. `.rubocop_with_todo.yml` is for the gates, until the todo
list for the older scripts is empty.

## Tests

1. Write the tests first and commit them red, in one commit.
2. Write the code.
3. Run the named tests for the change, then the gates once.

- Unit tests use Minitest. Acceptance tests use Varar documents under `test/varar/`.
- A test never writes under the real `~/.claude` or `~/.plastic`.
  `test/real_home_guard_test.rb` enforces this.
- A test that cannot fail proves nothing. Show once that a new guard fails.
