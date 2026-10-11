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
`.rubocop.yml` is for the editor. `.rubocop_with_todo.yml` is for the gates. It adds
`.rubocop_todo.yml`, which lists the offenses of older code.

- The Metrics cops are on for the whole repository. Standard turns them off, and
  `.rubocop.yml` turns them back on at RuboCop's default limits.
- A new or changed method or class that trips a Metrics cop is split. A disable comment never
  excuses it.
- `.rubocop_todo.yml` never gains an entry. It only shrinks as old code is fixed.
- A hash literal has one space inside its braces: `{ key: value }`. RuboCop corrects this.

## Smells and scores

- Reek finds code smells, such as a long parameter list or a method that uses another
  object's data more than its own. `.reek.yml` lists the smells of older code, and it never
  gains an entry. A new or changed method that smells is fixed.
- RubyCritic runs Reek, Flay and Flog, and scores the changed files out of 100. The gate fails
  a change that scores under 90.
- The kernel under `scripts/lib/plastic/` has no entry in either list, and it stays clean.
- Before a kernel section is called done, load it whole, lint it, and check its chains with
  `Routine.verify`, which raises with every fault at once.

## Tests

The patterns and the rules for every test are in
[Test a change](../../CONTRIBUTING.md#test-a-change). They are written in that one place.

## Branches

Each long-lived branch has one role.

- **`alpha` is for development.** Feature and stage pull requests stack on `alpha`, and CI
  runs the suite on each one.
- **`beta` is for local testing.** It is reset from `alpha` when a whole feature is merged
  there, and it never takes a direct commit. It releases on the `beta` channel, on a
  version that ends in `-beta.N`.
- **`main` is for everyday use.** It releases on the `latest` channel, on a version with
  no suffix.

A fix needed today goes to `main` in its own pull request. Then `main` is merged into `alpha`.
`scripts/release-check` checks that each branch releases the right kind of version.
