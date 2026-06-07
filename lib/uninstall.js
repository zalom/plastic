import { resolve } from 'node:path'
import { homedir } from 'node:os'
import { unlink, rm } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { getManifestFiles } from './manifest.js'
import { readJsonSafe, writeJsonAtomic, removeHooks } from './merge.js'

const AGENT_PATHS = {
  claude: {
    home: resolve(homedir(), '.claude'),
    manifest: resolve(homedir(), '.claude', 'plastic', 'manifest.json'),
    settings: resolve(homedir(), '.claude', 'settings.json'),
    hookPrefix: 'plastic-',
    extraDirs: [
      resolve(homedir(), '.claude', 'plastic'),
      resolve(homedir(), '.claude', 'skills', 'plastic'),
    ],
  },
  codex: {
    home: resolve(homedir(), '.agents'),
    manifest: resolve(homedir(), '.agents', 'plastic-manifest.json'),
    extraDirs: [resolve(homedir(), '.agents', 'skills', 'plastic')],
  },
  hermes: {
    home: resolve(homedir(), '.hermes'),
    manifest: resolve(homedir(), '.hermes', 'plastic-manifest.json'),
    extraDirs: [resolve(homedir(), '.hermes', 'skills', 'plastic')],
  },
}

export async function uninstallFromAgent(agentKey) {
  const config = AGENT_PATHS[agentKey]
  if (!config) return { success: false, reason: `Unknown agent: ${agentKey}` }
  if (!existsSync(config.home)) return { success: false, reason: `${config.home} not found` }

  let filesRemoved = 0

  const manifestFiles = await getManifestFiles(config.manifest)
  for (const filePath of manifestFiles) {
    if (existsSync(filePath)) {
      await unlink(filePath)
      filesRemoved++
    }
  }

  if (existsSync(config.manifest)) {
    await unlink(config.manifest)
    filesRemoved++
  }

  if (config.extraDirs) {
    for (const dir of config.extraDirs) {
      if (existsSync(dir)) {
        await rm(dir, { recursive: true })
      }
    }
  }

  if (config.settings && existsSync(config.settings)) {
    const settings = await readJsonSafe(config.settings)
    if (settings) {
      const cleaned = removeHooks(settings, config.hookPrefix)
      await writeJsonAtomic(config.settings, cleaned)
    }
  }

  return { success: true, filesRemoved }
}
