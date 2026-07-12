# encoding: UTF-8
# frozen_string_literal: true

# Parses a Codex `apply_patch` command envelope into an ordered list of file
# operations. Codex delivers file mutations as a V4A diff envelope in
# tool_input.command, not a clean file_path+content pair, and ONE apply_patch call
# can bundle several files. This is the single translation the Codex gate shims
# need; the Ruby gate/savepoint cores stay payload-agnostic behind it.
#
# Guide-settled shapes consumed here (intent 102, Decision 0, owner ruling):
# [guide Part 3] the `~/.codex/hooks.json` registration schema (consumed by
# HookRegistry.codex_hooks_json and merge_codex_hooks, not this file). [guide
# Part 4] the hook stdin schema, including `tool_input.command` as the carrier of
# the apply_patch envelope text (consumed by scripts/codex-hook).
#
# Residual gap (in neither the guide nor 181, per Decision 14): the apply_patch
# V4A envelope INNER grammar parsed below (`*** Begin/End Patch`, `*** Add/Update/
# Delete File:`, `*** Move to:`, `+`/`-`/context lines) is not primary-sourced.
# There is no live Codex to verify it against (the owner has none installed), so
# this parser is built to the best-known public V4A shape and FAILS OPEN on
# anything else. Returns [] and warns on any missing or unparseable envelope:
# gates fail OPEN (orchestrator-locks fail-open rule). The PostToolUse gate-check
# artifact backstop re-validates the intent file after the write, so a fail-open
# create-gate is still netted. A real Codex run after delivery is the only future
# check on this residual.
module ApplyPatchEnvelope
  module_function

  Op = Struct.new(:op, :path, :added_content, keyword_init: true)

  BEGIN_MARK = "*** Begin Patch"
  END_MARK   = "*** End Patch"
  ADD_RE     = /\A\*\*\* Add File: (.+)\z/
  UPDATE_RE  = /\A\*\*\* Update File: (.+)\z/
  DELETE_RE  = /\A\*\*\* Delete File: (.+)\z/
  MOVE_RE    = /\A\*\*\* Move to: (.+)\z/

  # command may be a String or (per Step 1) an Array of argv; normalize to the
  # patch text by scanning for the Begin/End markers regardless of wrapping.
  def parse(command)
    text = command.is_a?(Array) ? command.join("\n") : command.to_s
    b = text.index(BEGIN_MARK)
    e = text.index(END_MARK)
    return warn_empty("no Begin/End Patch markers") if b.nil? || e.nil? || e < b

    body = text[(b + BEGIN_MARK.length)...e]
    ops = []
    current = nil
    body.each_line do |raw|
      line = raw.chomp
      if (m = ADD_RE.match(line))
        current = Op.new(op: :add, path: m[1].strip, added_content: +"")
        ops << current
      elsif (m = UPDATE_RE.match(line))
        current = Op.new(op: :update, path: m[1].strip, added_content: +"")
        ops << current
      elsif (m = DELETE_RE.match(line))
        current = Op.new(op: :delete, path: m[1].strip, added_content: nil)
        ops << current
      elsif (m = MOVE_RE.match(line)) && current
        current.path = m[1].strip # rename target becomes the effective path
      elsif current && current.added_content && line.start_with?("+")
        current.added_content << line[1..].to_s << "\n"
      end
      # context (' '), removed ('-'), and '@@' lines are ignored for added_content
    end
    ops
  rescue StandardError => e
    warn_empty("parse error: #{e.message}")
  end

  def warn_empty(reason)
    $stderr.puts "plastic apply_patch parse: #{reason}; gate fails open"
    []
  end
end
