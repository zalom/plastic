import { installClaudeCode } from './claude-code.js'
import { installCodexCli } from './codex-cli.js'
import { installHermes } from './hermes.js'

const adapters = {
  claude: installClaudeCode,
  codex: installCodexCli,
  hermes: installHermes,
}

export async function installForAgent(agentKey, packageRoot, plasticHome, version, force) {
  const adapter = adapters[agentKey]
  if (!adapter) {
    return { success: false, reason: `No adapter for ${agentKey}` }
  }
  return adapter(packageRoot, plasticHome, version, force)
}
