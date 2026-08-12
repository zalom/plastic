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
# Grammar provenance (intent 239, 2026-08-12). The V4A envelope grammar parsed below
# is primary-sourced: it is embedded verbatim in the native codex binary and was
# extracted from codex-cli 0.146.0 into test/fixtures/codex-v4a-grammar.txt, which
# carries the binary's path, size and SHA256 in its header.
# test/codex_v4a_grammar_test.rb checks this parser's markers against that grammar,
# and a live test re-extracts from an installed binary so the fixture cannot drift
# (it skips cleanly on a machine with no codex).
#
# Two deliberate differences from the real grammar, both in the safe direction:
# codex requires the envelope's first line to be "*** Begin Patch" and its last to be
# "*** End Patch", while this parser scans for the markers on any line of the
# payload, not only the first and last; and "*** Environment ID:", a real production
# of the grammar, is ignored here rather than parsed, because it names no file
# operation. Both markers still must form a WHOLE LINE (start-of-text or a
# preceding LF, and end-of-text or a following LF): per add_line: "+" /(.*)/ LF, a
# content line such as "+*** End Patch" is legal file content, not a terminator, so a
# bare substring search would misparse it as the real marker (see
# line_anchored_index below). Anything else unparseable FAILS OPEN: parse returns []
# and warns, so gates allow the write (orchestrator-locks fail-open rule), and the
# PostToolUse gate-check backstop re-validates the intent file after the write
# lands.
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
    b = line_anchored_index(text, BEGIN_MARK, 0)
    return warn_empty("no Begin/End Patch markers") if b.nil?

    e = line_anchored_index(text, END_MARK, b + BEGIN_MARK.length)
    return warn_empty("no Begin/End Patch markers") if e.nil?

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

  # Finds the first occurrence of `mark` starting at or after `from` that forms a
  # WHOLE LINE: immediately preceded by start-of-text or a newline, and immediately
  # followed by end-of-text or a newline. A bare `text.index(mark)` would also match
  # `mark` sitting inside a longer line, such as the content line "+*** End Patch"
  # (legal per add_line: "+" /(.*)/ LF), which is not a terminator.
  def line_anchored_index(text, mark, from)
    pos = from
    loop do
      idx = text.index(mark, pos)
      return nil if idx.nil?

      line_start = idx.zero? || text[idx - 1] == "\n"
      after = idx + mark.length
      line_end = after == text.length || text[after] == "\n"
      return idx if line_start && line_end

      pos = idx + 1
    end
  end
end
