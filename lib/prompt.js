import { createInterface } from 'node:readline'

const AGENTS = [
  { key: 'claude', name: 'Claude Code', dir: '~/.claude', flag: '--claude' },
  { key: 'codex', name: 'Codex CLI', dir: '~/.agents', flag: '--codex' },
  { key: 'hermes', name: 'Hermes', dir: '~/.hermes', flag: '--hermes' },
]

export function parseFlags(argv) {
  const flags = { agents: [], force: false, uninstall: false, help: false }

  for (const arg of argv) {
    if (arg === '--all') flags.agents = AGENTS.map(a => a.key)
    else if (arg === '--force') flags.force = true
    else if (arg === '--uninstall') flags.uninstall = true
    else if (arg === '--help' || arg === '-h') flags.help = true
    else {
      const agent = AGENTS.find(a => a.flag === arg)
      if (agent) flags.agents.push(agent.key)
    }
  }

  return flags
}

export async function promptAgents() {
  if (!process.stdin.isTTY) {
    return ['claude']
  }

  const rl = createInterface({ input: process.stdin, output: process.stdout })
  const ask = (q) => new Promise(resolve => rl.question(q, resolve))

  console.log('\nWhich agents should Plastic register for?\n')
  AGENTS.forEach((a, i) => console.log(`  ${i + 1}. ${a.name} (${a.dir})`))
  console.log(`  ${AGENTS.length + 1}. All`)
  console.log()

  const answer = await ask('Select (comma-separated numbers, or Enter for Claude Code): ')
  rl.close()

  if (!answer.trim()) return ['claude']

  const nums = answer.split(',').map(n => parseInt(n.trim(), 10)).filter(n => !isNaN(n))

  if (nums.includes(AGENTS.length + 1)) return AGENTS.map(a => a.key)

  return nums
    .filter(n => n >= 1 && n <= AGENTS.length)
    .map(n => AGENTS[n - 1].key)
}

export function getAgentConfig(key) {
  return AGENTS.find(a => a.key === key)
}

export function showHelp() {
  console.log(`
plastic - Intent-driven idea development system

Usage:
  npx @zalom/plastic@latest [options]

Options:
  --claude      Install for Claude Code
  --codex       Install for Codex CLI
  --hermes      Install for Hermes
  --all         Install for all supported agents
  --force       Overwrite existing files without prompting
  --uninstall   Remove Plastic from agent directories
  -h, --help    Show this help

Examples:
  npx @zalom/plastic@latest              Interactive agent selection
  npx @zalom/plastic@latest --claude     Install for Claude Code only
  npx @zalom/plastic@latest --all        Install for all agents
  npx @zalom/plastic@latest --uninstall  Remove from agent directories
`)
}

export { AGENTS }
