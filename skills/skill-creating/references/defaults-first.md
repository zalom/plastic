# Defaults First

This chapter holds the Plastic-first, delegate-by-exception rule for naming an external skill as a default.

### Defaults-First

Plastic stands on its own. Skills and agents use Plastic's own defaults; an
external skill (for example `superpowers:*`) is opt-in, never load-bearing.

- **Default to Plastic, delegate by exception.** Name the Plastic-native path as
  the default. Delegate to an external skill only when (a) it is available in the
  harness, or (b) the user explicitly asks for it. A user without that plugin must
  still get the core behavior.
- **Phrase external skills as enhancements.** Write "use Plastic's native X by
  default; if `superpowers:<skill>` is available, or the user prefers it, delegate
  to it" never "delegate to `superpowers:<skill>`" as the only path.
- **Optional dependencies detect then degrade.** `qmd` is the reference shape:
  `scripts/lib/qmd_sync.rb` detects the binary first and every verb no-ops cleanly
  when it is absent (see `scripts/qmd-sync`). Optional CLIs and MCP servers follow
  the same detect-then-skip pattern, so a missing tool never crashes a session.
- **Legitimate hard dependencies are exempt.** Ruby, Node, git, and POSIX tools are
  the cost of running Plastic, not silent coupling. The principle targets accidental
  dependence on external skills doing work Plastic should do itself.
