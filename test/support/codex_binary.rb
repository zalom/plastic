# encoding: UTF-8
# frozen_string_literal: true

require "digest"

# Locates the native codex binary that carries the embedded V4A grammar (intent 239).
# The `codex` on PATH is a JS shim with no grammar in it, so resolution globs the
# platform package and then CONFIRMS by content anchor. Candidates are a parameter,
# never an environment variable: the project forbids an ENV or global config seam in
# tests, and a content-anchored resolver cannot pick the wrong file anyway.
module CodexBinary
  module_function

  ANCHOR = "start: begin_patch hunk+ end_patch\nbegin_patch:"
  STOP = "The `apply_patch` tool"
  CHUNK = 4 * 1024 * 1024
  OVERLAP = 64 * 1024
  MIN_SIZE = 10 * 1024 * 1024

  DEFAULT_CANDIDATES = [
    "~/.local/share/mise/installs/node/*/lib/node_modules/@openai/codex/node_modules/@openai/codex-*/vendor/*/bin/codex",
    "/usr/local/lib/node_modules/@openai/codex/node_modules/@openai/codex-*/vendor/*/bin/codex",
    "/opt/homebrew/lib/node_modules/@openai/codex/node_modules/@openai/codex-*/vendor/*/bin/codex",
    "~/.npm-global/lib/node_modules/@openai/codex/node_modules/@openai/codex-*/vendor/*/bin/codex",
  ].freeze

  # Returns the absolute path of the first candidate that is large enough AND
  # actually contains the grammar anchor, or nil.
  def resolve(candidates: DEFAULT_CANDIDATES)
    candidates.flat_map { |pat| Dir.glob(File.expand_path(pat)) }
              .uniq { |p| File.realpath(p) rescue p }
              .find { |p| File.file?(p) && File.size(p) >= MIN_SIZE && offset_of(p, ANCHOR) }
  end

  # Chunked scan with overlap: the binary is ~271 MB and must not be slurped whole.
  def offset_of(path, needle)
    off = 0
    File.open(path, "rb") do |f|
      prev = +""
      while (buf = f.read(CHUNK))
        hay = prev + buf
        i = hay.index(needle)
        return off - prev.bytesize + i if i
        prev = hay[-OVERLAP..] || hay
        off += buf.bytesize
      end
    end
    nil
  end

  # The grammar block, verbatim, from the anchor up to (not including) STOP.
  def grammar(path)
    i = offset_of(path, ANCHOR) or return nil
    raw = File.open(path, "rb") { |f| f.seek(i); f.read(4096) }
    stop = raw.index(STOP) or return nil
    raw[0, stop]
  end

  # Strings that establish codex's own strictness and tool shape (spec AC13).
  STRICTNESS_STRINGS = [
    "The first line of the patch must be",
    "do not wrap the patch in JSON",
    "apply_patch_freeform",
    "*** Environment ID: ",
    "*** Move to: ",
    "*** End of File",
  ].freeze

  def carries?(path, needle)
    !offset_of(path, needle).nil?
  end
end
