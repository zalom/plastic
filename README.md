# Plastic

> Intent-driven state management for AI coding sessions.
> Named after **neuroplasticity** — adaptive, malleable, dynamic, resilient.

## What Is This?

Plastic implements the "Intent → Build → Observe → Repeat" SDLC with Zettelkasten-inspired linking. All project state lives in `.plastic/`. Everything is an intent.

## Installation

### 1. Register the marketplace

Add to `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "plastic": {
      "source": { "source": "github", "repo": "zalom/plastic" }
    }
  }
}
```

### 2. Install the plugin

```bash
claude plugin add plastic@plastic
```

### 3. Initialize in your project

```bash
# In your project directory, run:
/plastic:install
```

## Prerequisites

Plastic hooks use Ruby or Node.js for generating deterministic directory hashes. **One** of the following must be available:

### macOS / Linux
Ruby is pre-installed. No action needed.

```bash
# Verify:
ruby -r digest -e 'puts Digest::SHA256.hexdigest("test").to_i(16).to_s(36)[0,6]'
```

### Windows

**Option A — WSL (recommended):**
```bash
wsl ruby -r digest -e 'puts Digest::SHA256.hexdigest("test").to_i(16).to_s(36)[0,6]'
```

**Option B — Node.js:**
```bash
node -e "const c=require('crypto');console.log(BigInt('0x'+c.createHash('sha256').update(process.argv[1]).digest('hex')).toString(36).slice(0,6))" "test"
```

**Option C — Install Ruby:**
Download from https://rubyinstaller.org/ or `winget install RubyInstallerTeam.Ruby`.

## Directory Structure

```
.plastic/
├── config.yml          # Plugin configuration
├── INDEX.md            # Brain's entry point
└── store/
    └── NNN--three-to-five-words-XXXXXX/
        ├── intent.md       # Always present
        ├── spec.md         # Optional (brainstorming output)
        ├── plan.md         # Optional (implementation plan)
        ├── checklist.md    # Optional (progress tracking)
        └── savepoint.md    # Optional (session state)
```

## Skills

| Skill | Purpose |
|-------|---------|
| `install` | Initialize `.plastic/` in a new project |
| `creating-intent` | Create a new intent with directory, hash, and INDEX.md entry |
| `savepoint` | Save active intent state before context reset |
| `continuing` | Resume from savepoint after `/clear` |
| `linking-intents` | Connect intents via Zettelkasten links |
| `managing-index` | Curate INDEX.md structure note |
| `executing-plan` | Execute plans via subagent-driven (default) or inline mode |

## Agents

| Agent | Purpose |
|-------|---------|
| `intent-curator` | Maintains INDEX.md health, suggests links |
| `future-intent-researcher` | Researches parked future intents |

## License

MIT
