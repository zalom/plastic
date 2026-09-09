# ACTION_1: clear RUBYOPT in bin/plastic.js and make its failure message honest

Intent: 235, Make the first install work on a clean Mac.
Satisfies: AC6. Preserves AC2, AC3, AC9, AC10.

## Context you need (do not go looking for it)

`bin/plastic.js` is the npx entry point. It spawns `ruby scripts/<verb>.rb` with
`execFileSync`. Today it passes the parent environment straight through, so a shell that exports
`RUBYOPT=--yjit` hands `--yjit` to the child ruby. On a clean Mac that child is
`/usr/bin/ruby` 2.6.10, which does not know `--yjit`, so it dies before printing anything.
`execFileSync` throws, and the `catch` block prints a hardcoded line claiming Ruby was
"not found". That is false: Ruby was found, it crashed on a flag.

With `RUBYOPT` cleared, the child runs, `scripts/install.rb` reaches its preflight gate, and
preflight prints the true message naming the real version. The `catch` block then only fires when
ruby genuinely cannot be executed, so its text must stop claiming a version problem.

## Where you work

Worktree (all edits go here):
`/Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac`

File: `/Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac/bin/plastic.js`

If Edit or Write is denied or writes to the wrong tree (concurrent sibling jobs can clobber the
worktree pointer), fall back to a Bash ruby write with the absolute path above and ` # plastic-ok`
appended to the command. Use `String#sub` with the BLOCK form so nothing in the replacement text
is interpreted.

## Edit 1: clear RUBYOPT (around line 46)

BEFORE (match this text exactly):

```js
try {
  execFileSync('ruby', [script, ...rest], {
    stdio: 'inherit',
    env: { ...process.env, PLASTIC_PACKAGE_ROOT: packageRoot },
  })
```

AFTER:

```js
try {
  execFileSync('ruby', [script, ...rest], {
    stdio: 'inherit',
    // RUBYOPT: '' last, after the spread, so a global RUBYOPT (for example --yjit)
    // cannot reach a ruby that does not know the flag. A machine with an old ruby
    // must get preflight's real message, not a crash.
    env: { ...process.env, PLASTIC_PACKAGE_ROOT: packageRoot, RUBYOPT: '' },
  })
```

`RUBYOPT: ''` must come AFTER the `...process.env` spread. Before it, the spread overwrites it
and the fix does nothing.

## Edit 2: honest catch message (around line 51)

BEFORE (match this text exactly):

```js
} catch (err) {
  if (err.status) process.exit(err.status)
  // Ruby cannot run to print its own message when it is missing, so this
  // mirrors scripts/lib/preflight.rb's FATAL block word for word.
  console.error('Plastic needs Ruby 3.0.0 or newer to run its scripts (found not found).')
  console.error('Install a pinned Ruby with mise:')
  console.error('  curl https://mise.run | sh        # only if mise is not installed yet')
  console.error('  mise use --global ruby@3.3')
  console.error('Then re-run the Plastic installer.')
  process.exit(1)
}
```

AFTER:

```js
} catch (err) {
  if (err.status) process.exit(err.status)
  // We only get here when ruby could not be executed at all. A ruby that runs but is
  // too old exits with a status, handled on the line above, and prints its own real
  // message from scripts/lib/preflight.rb naming the version actually found.
  if (err.code === 'ENOENT') {
    console.error('Plastic needs Ruby 3.0.0 or newer to run its scripts (ruby was not found on PATH).')
    console.error('Install a pinned Ruby with mise:')
    console.error('  curl https://mise.run | sh        # only if mise is not installed yet')
    console.error('  mise use --global ruby@3.3')
    console.error('Then re-run the Plastic installer.')
  } else {
    console.error(`Plastic could not run ruby: ${err.message}`)
    console.error('Check that `ruby -v` works in this shell, then re-run the Plastic installer.')
  }
  process.exit(1)
}
```

## Hard rules for this file

- Do NOT touch line 3 or line 30. Both already contain an em-dash. They are pre-existing lines.
  If you reflow, re-indent or re-save them as changed lines they become ADDED lines carrying an
  em-dash and they break AC10.
- No added line may contain an em-dash or an en-dash. Use a comma, a period or a colon.
- Do NOT add any code path that runs `curl https://mise.run`, `mise use` or `mise install`. This
  file only PRINTS those instructions. Adding an auto-install branch breaks AC3.
- Do not add or reference Spinel anywhere (AC2).

## Verify

1. Syntax parses (the package is `"type": "module"`, so check it as a module):

```
cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac
node --input-type=module --check < bin/plastic.js && echo "CHECK-OK"
```

Verified working on this machine (node v22.22.0). Must print `CHECK-OK` and exit 0.

2. The real AC6 transcript. This reproduces the clean-Mac case on this machine by putting only
`/usr/bin` on PATH, so bare `ruby` resolves to the system Ruby 2.6.10, and by exporting the
crashing flag:

```
cd /Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac
SCRATCH=$(mktemp -d)
HOME="$SCRATCH" PATH=/usr/bin RUBYOPT=--yjit "$(command -v node)" bin/plastic.js install --claude --force
echo "exit=$?"
```

EXPECTED after the fix (this is the acceptance evidence, capture the output):

```
Plastic needs Ruby 3.0.0 or newer to run its scripts (found 2.6.10).
Install a pinned Ruby with mise:
  curl https://mise.run | sh        # only if mise is not installed yet
  mise use --global ruby@3.3
Then re-run the Plastic installer.
```

The words "found not found" must NOT appear. The version 2.6.10 must appear. Then clean up:

```
rm -rf "$SCRATCH"
```

3. Confirm the false string is gone from the file:

```
grep -n "found not found" /Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac/bin/plastic.js
```

Must print nothing.

4. Confirm the clearing is present and correctly ordered:

```
grep -n "RUBYOPT" /Users/zlatko/apps/personal/plastic/.claude/worktrees/235--install-on-a-clean-mac/bin/plastic.js
```

Must show `RUBYOPT: ''` on the env line, after `...process.env`.

## Done when

`bin/plastic.js` passes `RUBYOPT: ''` to the child, the transcript in step 2 shows the true
version, and no added line carries an em-dash or en-dash.
