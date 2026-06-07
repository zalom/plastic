import { resolve } from 'node:path'
import { homedir } from 'node:os'
import { mkdir, copyFile, readdir, stat } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { createManifest } from '../manifest.js'

async function copyDirRecursive(src, dest) {
  const files = []
  await mkdir(dest, { recursive: true })
  const entries = await readdir(src)
  for (const entry of entries) {
    const srcPath = resolve(src, entry)
    const destPath = resolve(dest, entry)
    const s = await stat(srcPath)
    if (s.isDirectory()) {
      const nested = await copyDirRecursive(srcPath, destPath)
      files.push(...nested)
    } else if (s.isFile()) {
      await copyFile(srcPath, destPath)
      files.push(destPath)
    }
  }
  return files
}

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
    const copied = await copyDirRecursive(skillsSource, SKILLS_DIR)
    installedFiles.push(...copied)
  }

  await createManifest(installedFiles, MANIFEST_PATH)

  return { success: true, filesWritten: installedFiles.length }
}
