import { readFile, writeFile, rename } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { tmpdir } from 'node:os'
import { randomBytes } from 'node:crypto'

export async function readJsonSafe(filePath) {
  if (!existsSync(filePath)) return null

  try {
    const content = await readFile(filePath, 'utf8')
    return JSON.parse(content)
  } catch {
    try {
      const content = await readFile(filePath, 'utf8')
      const stripped = content.replace(/\/\/[^\n]*/g, '').replace(/,(\s*[}\]])/g, '$1')
      return JSON.parse(stripped)
    } catch {
      return null
    }
  }
}

export async function writeJsonAtomic(filePath, data) {
  const content = JSON.stringify(data, null, 2) + '\n'
  const tmpPath = resolve(dirname(filePath), `.plastic-tmp-${randomBytes(4).toString('hex')}`)
  await writeFile(tmpPath, content)
  await rename(tmpPath, filePath)
}

export function mergeHooks(existing, plasticHooks) {
  const hooks = existing.hooks || {}

  for (const [event, entries] of Object.entries(plasticHooks)) {
    if (!hooks[event]) hooks[event] = []

    for (const entry of entries) {
      const alreadyExists = hooks[event].some(h =>
        h.command === entry.command ||
        (h.hooks && h.hooks.some(hh => hh.command === entry.command))
      )
      if (!alreadyExists) {
        hooks[event].push(entry)
      }
    }
  }

  existing.hooks = hooks
  return existing
}

export function removeHooks(existing, prefix) {
  if (!existing.hooks) return existing

  for (const [event, entries] of Object.entries(existing.hooks)) {
    existing.hooks[event] = entries.filter(e => {
      const cmd = e.command || (e.hooks && e.hooks[0]?.command) || ''
      return !cmd.includes(prefix)
    })
    if (existing.hooks[event].length === 0) {
      delete existing.hooks[event]
    }
  }

  if (Object.keys(existing.hooks).length === 0) {
    delete existing.hooks
  }

  return existing
}
