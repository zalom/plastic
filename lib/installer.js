import { resolve } from 'node:path'
import { homedir } from 'node:os'
import { parseFlags, promptAgents, getAgentConfig, showHelp } from './prompt.js'
import { bootstrap, distribute } from './bootstrap.js'
import { installForAgent } from './adapters/index.js'
import { uninstallFromAgent } from './uninstall.js'

const PLASTIC_HOME = resolve(homedir(), '.plastic')
const VERSION_FILE = resolve(PLASTIC_HOME, 'VERSION')

export async function run(argv) {
  const flags = parseFlags(argv)

  if (flags.help) {
    showHelp()
    return
  }

  const packageRoot = new URL('..', import.meta.url).pathname
  const pkg = JSON.parse(
    await import('node:fs/promises').then(fs => fs.readFile(resolve(packageRoot, 'package.json'), 'utf8'))
  )
  const version = pkg.version

  console.log(`\n🧠 Plastic v${version}\n`)

  if (flags.uninstall) {
    await handleUninstall(flags)
    return
  }

  const agents = flags.agents.length > 0 ? flags.agents : await promptAgents()

  if (agents.length === 0) {
    console.log('No agents selected. Nothing to do.')
    return
  }

  const isUpdate = await detectExisting()
  const mode = isUpdate ? 'update' : 'install'

  console.log(`Mode: ${mode}`)
  console.log(`Agents: ${agents.map(a => getAgentConfig(a)?.name).join(', ')}`)
  console.log()

  await distribute(packageRoot, PLASTIC_HOME, version, mode)

  if (!isUpdate) {
    await bootstrap(PLASTIC_HOME)
  }

  const results = []
  for (const agentKey of agents) {
    const config = getAgentConfig(agentKey)
    if (!config) {
      console.log(`  ⚠️  Unknown agent: ${agentKey} — skipping`)
      continue
    }

    const result = await installForAgent(agentKey, packageRoot, PLASTIC_HOME, version, flags.force)
    results.push({ agent: config.name, ...result })
  }

  console.log('\n— Results —\n')
  for (const r of results) {
    if (r.success) {
      console.log(`  ✅ ${r.agent}: ${r.filesWritten} files installed`)
    } else {
      console.log(`  ⚠️  ${r.agent}: ${r.reason}`)
    }
  }

  const installed = results.filter(r => r.success)
  if (installed.length > 0) {
    console.log(`\n✅ Plastic v${version} ${mode === 'update' ? 'updated' : 'installed'}.`)
    console.log(`   Registered for: ${installed.map(r => r.agent).join(', ')}`)
    console.log(`   Run /clear (or restart your agent) to pick up new conventions.\n`)
  }
}

async function detectExisting() {
  const { existsSync } = await import('node:fs')
  return existsSync(resolve(PLASTIC_HOME, 'INDEX.md'))
}

async function handleUninstall(flags) {
  const agents = flags.agents.length > 0 ? flags.agents : ['claude']

  for (const agentKey of agents) {
    const config = getAgentConfig(agentKey)
    if (!config) continue
    const result = await uninstallFromAgent(agentKey)
    if (result.success) {
      console.log(`  ✅ ${config.name}: uninstalled (${result.filesRemoved} files removed)`)
    } else {
      console.log(`  ⚠️  ${config.name}: ${result.reason}`)
    }
  }

  console.log('\n  Note: ~/.plastic/ (your intent store) is preserved.\n')
}
