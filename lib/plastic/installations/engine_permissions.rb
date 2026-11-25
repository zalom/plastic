# frozen_string_literal: true

require_relative "files"

module Plastic
  module Installations
    # EnginePermissions: the engine deny rule. A permissions.deny
    # block merged into settings.json at install so the engine directories are not
    # editable by a dispatched agent.
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
    # merge_into is a pure function; merge_file owns the read-modify-write
    # against settings.json.
    module EnginePermissions
      module_function

      ENTRIES = [
        "Edit(~/.plastic/skills/**)",
        "Edit(~/.plastic/hooks/**)"
      ].freeze

      # Entries an earlier install wrote and this one does not. A merge takes them
      # out and the record lists them, so an uninstall takes them out too.
      RETIRED = [
        "Edit(~/.plastic/scripts/**)"
      ].freeze

      # Merges ENTRIES into the settings file at path. A file that exists and
      # is not JSON stays as it is, and the result is false.
      def merge_file(path)
        settings = Files.read_json(path)
        return false if settings.nil? && File.exist?(path)

        Files.write_json(path, merge_into(settings || {}))
        true
      end

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

        deny -= RETIRED
        ENTRIES.each { |entry| deny << entry unless deny.include?(entry) }

        permissions["deny"] = deny
        settings["permissions"] = permissions
        settings
      end
    end
  end
end
