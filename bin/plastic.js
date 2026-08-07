#!/usr/bin/env node

// Thin shim — npx entry point that dispatches a subcommand to the matching Ruby verb script.
// All logic lives in scripts/<verb>.rb. JS is only the distribution + dispatch mechanism.
//
//   npx @zalom/plastic install   [flags]
//   npx @zalom/plastic update    [flags]
//   npx @zalom/plastic uninstall [flags]
//   npx @zalom/plastic rollback  [flags]
//
// Back-compat: a bare `--uninstall` (no subcommand) routes to uninstall with a deprecation
// warning; no subcommand at all defaults to install (legacy behaviour, one release).

import { execFileSync } from 'node:child_process'
import { resolve } from 'node:path'
import { existsSync } from 'node:fs'

const VERBS = ['install', 'update', 'uninstall', 'rollback']
const packageRoot = new URL('..', import.meta.url).pathname
const argv = process.argv.slice(2)

let verb
let rest

if (VERBS.includes(argv[0])) {
  verb = argv[0]
  rest = argv.slice(1)
} else if (argv.includes('--uninstall')) {
  // Deprecated: `--uninstall` as a flag instead of the `uninstall` subcommand.
  console.error('! plastic: `--uninstall` is deprecated — use `npx @zalom/plastic uninstall`. (works for now)')
  verb = 'uninstall'
  rest = argv.filter((a) => a !== '--uninstall')
} else {
  // No subcommand: legacy default to install (one release of grace).
  verb = 'install'
  rest = argv
}

const script = resolve(packageRoot, 'scripts', `${verb}.rb`)

if (!existsSync(script)) {
  console.error(`Error: scripts/${verb}.rb not found in package.`)
  process.exit(1)
}

try {
  execFileSync('ruby', [script, ...rest], {
    stdio: 'inherit',
    // Clear RUBYOPT last, after the spread, so a global setting (for example --yjit)
    // cannot reach a ruby that does not know the flag. A machine with an old ruby
    // must get preflight's real message, not a crash.
    env: { ...process.env, PLASTIC_PACKAGE_ROOT: packageRoot, RUBYOPT: '' },
  })
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
