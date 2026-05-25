---
name: uninstall
description: Use when the user wants to remove Plastic. Deregisters the plugin from the current agent (Claude Code, Cursor, etc.) and optionally deletes all data.
---

# Uninstall Plastic

## Procedure

### Step 1: Detect the current agent

Check environment variables to determine which agent is running:
- `$CLAUDE_PLUGIN_ROOT` → Claude Code
- `$CURSOR_PLUGIN_ROOT` → Cursor
- Otherwise → unknown agent

### Step 2: Deregister from the agent

**Claude Code:**
- Remove `"plastic"` from `extraKnownMarketplaces` in `~/.claude/settings.json`
- Remove `"plastic@plastic"` from `enabledPlugins` in `~/.claude/settings.json`
- Announce: "Plastic deregistered from Claude Code."

**Other agents:** Provide manual instructions for their deregistration process.

### Step 3: Offer the data decision

Present clearly:

```
Plastic is deregistered from [agent name].

Your intent store at ~/.plastic/ is untouched.

Would you like to delete your Plastic data now?

⚠️  WARNING: This permanently removes ALL intents, history,
and any projects in ~/.plastic/projects/.
This is irreversible.

a) Keep everything (recommended) — you can re-install Plastic later
b) Delete everything now — removes ~/.plastic/ entirely
```

### Step 4: Execute user's choice

- **Keep:** Done. Tell the user: "Your data is at ~/.plastic/. Re-install anytime with `/plastic:install`."
- **Delete:** Run `rm -rf ~/.plastic/` and confirm: "Plastic data deleted."
