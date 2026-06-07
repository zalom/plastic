import { resolve, join } from 'node:path'
import { mkdir, writeFile, readFile, copyFile, readdir, stat } from 'node:fs/promises'
import { existsSync } from 'node:fs'

export async function distribute(packageRoot, plasticHome, version, mode) {
  console.log(`  📦 ${mode === 'update' ? 'Updating' : 'Installing'} core files to ${plasticHome}`)

  await mkdir(plasticHome, { recursive: true })
  await mkdir(resolve(plasticHome, 'scripts'), { recursive: true })

  const coreFiles = [
    ['PLASTIC.md', 'PLASTIC.md'],
    ['deprecations.yml', 'deprecations.yml'],
    ['scripts/folgezettel-id', 'scripts/folgezettel-id'],
    ['scripts/read-config', 'scripts/read-config'],
  ]

  for (const [src, dest] of coreFiles) {
    const srcPath = resolve(packageRoot, src)
    const destPath = resolve(plasticHome, dest)
    if (existsSync(srcPath)) {
      await copyFile(srcPath, destPath)
    }
  }

  await writeFile(resolve(plasticHome, 'VERSION'), version + '\n')

  const { chmod } = await import('node:fs/promises')
  const scriptsDir = resolve(plasticHome, 'scripts')
  if (existsSync(scriptsDir)) {
    const scripts = await readdir(scriptsDir)
    for (const s of scripts) {
      await chmod(resolve(scriptsDir, s), 0o755)
    }
  }

  console.log(`  ✅ Core files synced (v${version})`)
}

export async function bootstrap(plasticHome) {
  console.log('  🌱 First install — bootstrapping store...')

  await mkdir(resolve(plasticHome, 'store'), { recursive: true })
  await mkdir(resolve(plasticHome, 'projects'), { recursive: true })

  const configPath = resolve(plasticHome, 'config.yml')
  if (!existsSync(configPath)) {
    await writeFile(configPath, `version: 3
execution_mode: subagent-driven
stale_threshold_days: 3
hash_length: 6
hash_algorithm: sha256-base36
max_slug_words: 5
agent:
  type: claude-code
  parallel_mode: agent-teams
`)
  }

  const projectsPath = resolve(plasticHome, 'projects.yml')
  if (!existsSync(projectsPath)) {
    await writeFile(projectsPath, `---
projects: {}
`)
  }

  const indexPath = resolve(plasticHome, 'INDEX.md')
  if (!existsSync(indexPath)) {
    await writeFile(indexPath, `# Index

## Active

## Future

## Clusters

## Abandoned

## Completed
`)
  }

  const agentsPath = resolve(plasticHome, 'AGENTS.md')
  if (!existsSync(agentsPath)) {
    await writeFile(agentsPath, `# Plastic — Agent Instructions

Read \`PLASTIC.md\` in this directory. It contains all Plastic conventions.
Follow it exactly. Never modify it — it is overwritten on plugin updates.

This file (\`AGENTS.md\`) is where project-specific rules live.

---
`)
  }

  console.log('  ✅ Store bootstrapped')
}
