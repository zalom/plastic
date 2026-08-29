# encoding: UTF-8
# frozen_string_literal: true

# Install-time harness text projection (intent 239). Plastic authors one skill tree,
# in Claude Code's dialect, and projects it per harness at COPY time. This mirrors the
# rewrite install_claude already performs on hook launchers ($SCRIPT_DIR/../scripts/ to
# $HOME/.plastic/scripts/, installer_core.rb:723-735); it is the same mechanism applied
# to instruction text instead of shell launchers.
#
# Pure String to String. No IO, no filesystem probing, no ENV reads: the caller supplies
# both the relative source path and the set of real skill directory names.
module HarnessText
  module_function

  PLUGIN_ROOT_TOKEN = "${CLAUDE_PLUGIN_ROOT}"

  # Spec D2: NOT "~/.plastic". Both executable call sites sit inside double-quoted
  # shell words, where a leading tilde does not expand. $HOME does, and it is the exact
  # form the install_claude hook rewrite already writes.
  PLUGIN_ROOT_CODEX = "$HOME/.plastic"

  # Spec D3: files that document Claude's placeholder convention TO SKILL AUTHORS are
  # exempt by path. The skill-authoring reference left the installed tree in 2.0
  # (intent 304), so the list is empty; the seam stays for the next such file.
  PLUGIN_ROOT_EXEMPT = [].freeze

  # Spec D4: an explicit root table, not one regex. The ~/.claude lines in the skill
  # corpus carry four different meanings; only these three have an exact Codex
  # equivalent. ~/.claude/hooks/... is deliberately absent (D5): Codex installs no
  # per-agent hook launchers, so there is no path to substitute into.
  CLAUDE_ROOTS_CODEX = {
    "~/.claude/skills" => "~/.agents/skills",
    "~/.claude/plastic" => "~/.agents/plastic",
    "~/.claude/settings.json" => "~/.codex/hooks.json",
  }.freeze

  def for_codex(text, rel_path:, skill_names:)
    out = text
    out = out.gsub(PLUGIN_ROOT_TOKEN, PLUGIN_ROOT_CODEX) unless PLUGIN_ROOT_EXEMPT.include?(rel_path)
    CLAUDE_ROOTS_CODEX.each { |from, to| out = out.gsub(from, to) }
    rewrite_skill_prefix(out, skill_names, "$")
  end

  # Spec D6. Two guards, both required:
  #   the negative lookbehind rejects any /plastic- that is part of a longer path
  #   ("../plastic-conventions/", "/tmp/plastic-{session}", "agents/plastic-*.md",
  #   "~/.claude/hooks/plastic-session-start");
  #   the name alternation, built from the real skills/ directory listing, rejects
  #   anything that is not an installed skill ("/plastic-lock" is a CLI script,
  #   "/plastic-enforcer" is an agent role).
  # Longest name first so /plastic-intent-continuing cannot match "continuing".
  def rewrite_skill_prefix(text, skill_names, prefix)
    return text if skill_names.nil? || skill_names.empty?
    alt = skill_names.sort_by { |n| -n.length }.map { |n| Regexp.escape(n) }.join("|")
    re = %r{(?<![\w./~*-])/plastic-(#{alt})(?![\w-])}
    text.gsub(re) { "#{prefix}plastic-#{Regexp.last_match(1)}" }
  end
end
