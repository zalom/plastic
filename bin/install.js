#!/usr/bin/env node

import { run } from '../lib/installer.js'

run(process.argv.slice(2)).catch(err => {
  console.error(`\n❌ ${err.message}`)
  process.exit(1)
})
