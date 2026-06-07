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
    const copied = await copyDirRecursive(skillsSource, SKILLS_DIR)
    installedFiles.push(...copied)
  }

  await createManifest(installedFiles, MANIFEST_PATH)

  return { success: true, filesWritten: installedFiles.length }
}
