# encoding: UTF-8
# frozen_string_literal: true

# EnginePermissions: the engine deny rule (intent 340b, G7c, n3). A permissions.deny
# block merged into settings.json at install so the engine directories are not
# editable by a dispatched agent (C25's self-preservation half).
#
# Claude Code accepts a Write(...) path rule and never consults it: Edit(...) is the
# rule that covers Write, MultiEdit and NotebookEdit. Every entry below names Edit,
# never Write, and every entry ends in /** because a bare directory path matches the
# directory itself, not the files under it.
#
# This is a second ownership mechanism, deliberately not a reuse of HookRegistry's
# merge, which knows its own entries by a plastic- launcher basename inside a command
# string. A deny entry is a bare string with no marker in it, so ownership here is
# exact-string membership in ENTRIES. The consequence is deliberate: an entry the
# owner has edited no longer matches the frozen string, so it is the owner's from
# that point on - the merge appends Plastic's own alongside it, and removal leaves
# the edited one in place untouched.
#
# Pure functions only: no file I/O here. InstallerCore#merge_engine_permissions and
# #remove_engine_permissions own the read-modify-write against settings.json,
# mirroring the split HookRegistry keeps from merge_claude_hooks.
module EnginePermissions
  module_function

  ENTRIES = [
    "Edit(~/.plastic/scripts/**)",
    "Edit(~/.plastic/skills/**)",
    "Edit(~/.plastic/hooks/**)",
    "Edit(~/.plastic/templates/**)",
  ].freeze

  # Returns a new settings hash with ENTRIES merged into permissions.deny, appended
  # (never duplicated) alongside whatever is already there. Survives a permissions
  # or deny value that is not the shape expected (row 3.12): a non-Hash permissions
  # value or a non-Array deny value is replaced rather than raised on. Never
  # mutates the argument.
  def merge_into(settings)
    settings = settings.is_a?(Hash) ? settings.dup : {}

    permissions = settings["permissions"]
    permissions = permissions.is_a?(Hash) ? permissions.dup : {}

    deny = permissions["deny"]
    deny = deny.is_a?(Array) ? deny.dup : []

    ENTRIES.each { |entry| deny << entry unless deny.include?(entry) }

    permissions["deny"] = deny
    settings["permissions"] = permissions
    settings
  end

  # Returns a new settings hash with exactly the ENTRIES strings removed from
  # permissions.deny, leaving every other entry (the owner's own deny rules, and
  # any Plastic entry the owner has since edited) untouched. Prunes the deny array
  # once it is empty, and the whole permissions block once nothing else remains
  # under it (row 3.10). A settings/permissions/deny shape that is not what is
  # expected is left alone rather than raised on (row 3.12's uninstall side).
  def remove_from(settings)
    return settings unless settings.is_a?(Hash)

    permissions = settings["permissions"]
    return settings unless permissions.is_a?(Hash)

    deny = permissions["deny"]
    return settings unless deny.is_a?(Array)

    settings = settings.dup
    permissions = permissions.dup
    deny = deny.reject { |entry| ENTRIES.include?(entry) }

    if deny.empty?
      permissions.delete("deny")
    else
      permissions["deny"] = deny
    end

    if permissions.empty?
      settings.delete("permissions")
    else
      settings["permissions"] = permissions
    end

    settings
  end
end
