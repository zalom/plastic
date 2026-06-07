import { resolve } from 'node:path'
import { homedir } from 'node:os'
import { mkdir, copyFile, readdir } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { createManifest } from '../manifest.js'

const HERMES_HOME = resolve(homedir(), '.hermes')
const SKILLS_DIR = resolve(HERMES_HOME, 'skills', 'plastic')
const MANIFEST_PATH = resolve(HERMES_HOME, 'plastic-manifest.json')

export async function installHermes(packageRoot, plasticHome, version, force) {
  if (!existsSync(HERMES_HOME)) {
    return { success: false, reason: `~/.hermes/ not found — Hermes not installed?` }
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
