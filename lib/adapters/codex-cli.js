import { resolve } from 'node:path'
import { homedir } from 'node:os'
import { mkdir, copyFile, readdir } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { createManifest } from '../manifest.js'

const AGENTS_HOME = resolve(homedir(), '.agents')
const CODEX_HOME = resolve(homedir(), '.codex')
const SKILLS_DIR = resolve(AGENTS_HOME, 'skills', 'plastic')
const MANIFEST_PATH = resolve(AGENTS_HOME, 'plastic-manifest.json')

export async function installCodexCli(packageRoot, plasticHome, version, force) {
  const hasCodex = existsSync(CODEX_HOME) || existsSync(AGENTS_HOME)

  if (!hasCodex) {
    return { success: false, reason: `~/.codex/ and ~/.agents/ not found — Codex CLI not installed?` }
  }

  await mkdir(SKILLS_DIR, { recursive: true })

  const installedFiles = []

  const skillsSource = resolve(packageRoot, 'skills')
  if (existsSync(skillsSource)) {
    const skillDirs = await readdir(skillsSource)
    for (const skillDir of skillDirs) {
      const skillSource = resolve(skillsSource, skillDir)
      const skillStat = await import('node:fs/promises').then(fs => fs.stat(skillSource))
      if (skillStat.isDirectory()) {
        const destDir = resolve(SKILLS_DIR, skillDir)
        await mkdir(destDir, { recursive: true })
        const files = await readdir(skillSource)
        for (const file of files) {
          const dest = resolve(destDir, file)
          await copyFile(resolve(skillSource, file), dest)
          installedFiles.push(dest)
        }
      }
    }
  }

  await createManifest(installedFiles, MANIFEST_PATH)

  return { success: true, filesWritten: installedFiles.length }
}
