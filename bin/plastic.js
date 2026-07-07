#!/usr/bin/env node

// Thin shim — npx entry point that dispatches a subcommand to the matching Ruby verb script.
// All logic lives in scripts/<verb>.rb. JS is only the distribution + dispatch mechanism.
//
//   npx @zalom/plastic install   [flags]
//   npx @zalom/plastic update    [flags]
//   npx @zalom/plastic uninstall [flags]
//   npx @zalom/plastic versions  [flags]
//
// Back-compat: a bare `--uninstall` (no subcommand) routes to uninstall with a deprecation
// warning; no subcommand at all defaults to install (legacy behaviour, one release).

import { execFileSync } from 'node:child_process'
import { resolve } from 'node:path'
import { existsSync } from 'node:fs'

const VERBS = ['install', 'update', 'uninstall', 'versions']
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
    env: { ...process.env, PLASTIC_PACKAGE_ROOT: packageRoot },
  })
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
