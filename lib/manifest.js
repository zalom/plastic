import { readFile, writeFile } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { resolve } from 'node:path'

export async function createManifest(files, manifestPath) {
  const entries = {}

  for (const filePath of files) {
    if (existsSync(filePath)) {
      const content = await readFile(filePath)
      entries[filePath] = createHash('sha256').update(content).digest('hex')
    }
  }

  const manifest = {
    version: '1',
    created: new Date().toISOString(),
    files: entries,
  }

  await writeFile(manifestPath, JSON.stringify(manifest, null, 2) + '\n')
  return manifest
}

export async function readManifest(manifestPath) {
  if (!existsSync(manifestPath)) return null

  try {
    const content = await readFile(manifestPath, 'utf8')
    return JSON.parse(content)
  } catch {
    return null
  }
}

export async function getManifestFiles(manifestPath) {
  const manifest = await readManifest(manifestPath)
  if (!manifest) return []
  return Object.keys(manifest.files || {})
}
