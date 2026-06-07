#!/usr/bin/env node

// Thin shim — npx entry point that delegates to the Ruby installer.
// All logic lives in scripts/install.rb. JS is only the distribution mechanism.

import { execFileSync } from 'node:child_process'
import { resolve } from 'node:path'
import { existsSync } from 'node:fs'

const packageRoot = new URL('..', import.meta.url).pathname
const installer = resolve(packageRoot, 'scripts', 'install.rb')

if (!existsSync(installer)) {
  console.error('Error: scripts/install.rb not found in package.')
  process.exit(1)
}

try {
  execFileSync('ruby', [installer, ...process.argv.slice(2)], {
    stdio: 'inherit',
    env: { ...process.env, PLASTIC_PACKAGE_ROOT: packageRoot },
  })
} catch (err) {
  if (err.status) process.exit(err.status)
  console.error('Error: Ruby is required to install Plastic.')
  console.error('  macOS: Ruby is pre-installed')
  console.error('  Linux: sudo apt install ruby / dnf install ruby')
  process.exit(1)
}
