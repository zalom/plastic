import { resolve } from 'node:path'
import { homedir } from 'node:os'
import { mkdir, copyFile, readdir } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { readJsonSafe, writeJsonAtomic, mergeHooks } from '../merge.js'
import { createManifest } from '../manifest.js'

const CLAUDE_HOME = resolve(homedir(), '.claude')
const SETTINGS_FILE = resolve(CLAUDE_HOME, 'settings.json')
const HOOKS_DIR = resolve(CLAUDE_HOME, 'hooks')
const SKILLS_DIR = resolve(CLAUDE_HOME, 'skills', 'plastic')
const PLASTIC_DIR = resolve(CLAUDE_HOME, 'plastic')
const MANIFEST_PATH = resolve(PLASTIC_DIR, 'manifest.json')

const PLASTIC_HOOKS = {
  SessionStart: [
    {
      type: 'command',
      command: `ruby ${resolve(CLAUDE_HOME, 'hooks', 'plastic-session-start.rb')}`,
      statusMessage: 'Loading Plastic context...',
    },
  ],
  PreCompact: [
    {
      type: 'command',
      command: `ruby ${resolve(CLAUDE_HOME, 'hooks', 'plastic-pre-compact.rb')}`,
      statusMessage: 'Saving Plastic intent state...',
    },
  ],
  PostToolUse: [
    {
      matcher: 'Write|Edit',
      type: 'command',
      command: `ruby ${resolve(CLAUDE_HOME, 'hooks', 'plastic-gate-check.rb')}`,
      statusMessage: 'Checking lifecycle gates...',
    },
  ],
  UserPromptSubmit: [
    {
      type: 'command',
      command: `ruby ${resolve(CLAUDE_HOME, 'hooks', 'plastic-user-prompt.rb')}`,
      statusMessage: 'Checking Plastic context...',
    },
  ],
}

export async function installClaudeCode(packageRoot, plasticHome, version, force) {
  if (!existsSync(CLAUDE_HOME)) {
    return { success: false, reason: `~/.claude/ not found — Claude Code not installed?` }
  }

  await mkdir(HOOKS_DIR, { recursive: true })
  await mkdir(SKILLS_DIR, { recursive: true })
  await mkdir(PLASTIC_DIR, { recursive: true })

  const installedFiles = []

  const hooksSource = resolve(packageRoot, 'hooks')
  if (existsSync(hooksSource)) {
    const hookFiles = (await readdir(hooksSource)).filter(f => f.endsWith('.rb') || f.endsWith('.sh'))
    for (const file of hookFiles) {
      const destName = file.startsWith('plastic-') ? file : `plastic-${file}`
      const dest = resolve(HOOKS_DIR, destName)
      await copyFile(resolve(hooksSource, file), dest)
      installedFiles.push(dest)
    }
  }

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

  const versionFile = resolve(PLASTIC_DIR, 'VERSION')
  const { writeFile } = await import('node:fs/promises')
  await writeFile(versionFile, version + '\n')
  installedFiles.push(versionFile)

  const settings = (await readJsonSafe(SETTINGS_FILE)) || {}
  if (settings === null) {
    return {
      success: false,
      reason: `Cannot parse ${SETTINGS_FILE} — refusing to modify. Fix JSON syntax and retry.`,
    }
  }

  const merged = mergeHooks(settings, PLASTIC_HOOKS)
  await writeJsonAtomic(SETTINGS_FILE, merged)

  await createManifest(installedFiles, MANIFEST_PATH)
  installedFiles.push(MANIFEST_PATH)

  return { success: true, filesWritten: installedFiles.length }
}
