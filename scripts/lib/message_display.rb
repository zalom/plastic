# encoding: UTF-8
# frozen_string_literal: true

require "fileutils"
require_relative "intent_screen"
require_relative "intent_screen_ansi"
require_relative "store_discovery"
require_relative "store_provisioning"

# MessageDisplay (intent 316a, O4/O5) - the Claude Code MessageDisplay hook
# handler. One process per streamed chunk of every assistant message
# (D11), so it must be cheap and decide fast. Pure: every dependency
# (tmp_root, plastic_home, color, now) is a constructor argument, never an
# ENV read, a Dir.pwd/Dir.home read, or the real Time.now — the thin CLI
# (scripts/hook-message-display) is the only place allowed to read any of
# those.
#
# Protocol (D13): chunk 0 decides, once, and nothing is ever blanked
# speculatively.
#   - Chunk 0 matches "## ▶ <id> · " (after leading whitespace only)
#     -> engage: buffer the delta, return "" (or splice immediately if also
#        final).
#   - Chunk 0 does not match, for any reason (a clean mismatch or a delta too
#     short to tell) -> no buffer is ever created, so this message renders
#     plain and every later chunk of it (index > 0, no buffer found) passes
#     through untouched. The two "does not engage" cases collapse into one
#     code path deliberately: neither one is ever revisited once chunk 0 has
#     run, so there is nothing to distinguish them on later chunks.
#   - Engaged, not final -> append the delta to the buffer, return "".
#   - Engaged, final -> resolve the intent directory (O5), render the ANSI
#     block, splice it over the plain screen's prefix inside the buffered
#     message (D16), delete the buffer, return the spliced whole message.
#   - Any failure while finalizing returns the buffered ORIGINAL, never nil
#     and never "" (D10): earlier chunks were already blanked, so passing
#     through at that point would leave a blank message where the answer was.
#   - `color: false` passes through from chunk 0 unconditionally and never
#     buffers or blanks anything (D12).
class MessageDisplay
  MARKER_RE = /\A## ▶ (\S+) · /.freeze
  BUFFER_DIR_NAME = "plastic-message-display"
  BUFFER_MAX_AGE_SECONDS = 3600

  def initialize(tmp_root:, plastic_home:, color:, now:)
    @tmp_root = tmp_root
    @plastic_home = plastic_home
    @color = color
    @now = now
  end

  def handle(payload)
    return nil unless @color
    return nil unless payload.is_a?(Hash)

    prune_old_buffers

    message_id = payload["message_id"].to_s
    session_id = payload["session_id"].to_s
    delta = payload["delta"].to_s
    final = payload["final"] == true
    index = payload["index"]
    cwd = payload["cwd"].to_s

    return nil if message_id.empty? || session_id.empty?

    path = self.class.buffer_path(tmp_root: @tmp_root, session_id: session_id, message_id: message_id)

    if index == 0
      stripped = delta.sub(/\A[ \t]+/, "")
      return nil unless stripped.match?(MARKER_RE)

      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, delta)
    else
      return nil unless File.exist?(path)

      File.open(path, "a") { |f| f.write(delta) }
    end

    return "" unless final

    buffered = File.read(path)
    begin
      finalize(buffered, cwd)
    rescue StandardError
      buffered
    ensure
      FileUtils.rm_f(path)
    end
  end

  # The buffer file path both this class and the bash launcher (hooks/message-
  # display) must agree on byte for byte (matrix 40): the launcher checks this
  # exact path's existence to decide whether chunk > 0 of an engaged message
  # gets handed to Ruby at all.
  def self.buffer_path(tmp_root:, session_id:, message_id:)
    File.join(tmp_root, BUFFER_DIR_NAME, session_id, message_id)
  end

  private

  def finalize(buffered, cwd)
    # Same "after leading whitespace only" rule chunk 0 used to engage in the
    # first place (matched on the stripped delta, but the buffer keeps every
    # byte verbatim for the splice) — without stripping here too, a message
    # chunk 0 correctly recognized could still fail to yield an id here.
    m = buffered.sub(/\A[ \t]+/, "").match(MARKER_RE)
    return buffered unless m

    id = m[1]
    resolved = resolve_intent_dir(id, cwd)
    return buffered unless resolved

    intent_dir = resolved[:intent_dir]
    # IntentScreen/IntentScreenAnsi's store_root: is the TIER root (what HOLDS
    # store/ — e.g. .../projects/<slug> or plastic_home itself), never the
    # store/ directory itself. store_fields tells "global" from "project:x"
    # by checking whether store_root's OWN parent is named "projects"; handing
    # it the store/ directory shifts that check one level and always reads
    # "global", even for a real project (caught by matrix 36's own test).
    store_root = resolved[:root]
    ansi = IntentScreenAnsi.render(intent_dir: intent_dir, store_root: store_root, color: true)
    plain = IntentScreen.render(intent_dir: intent_dir, store_root: store_root, template: File.read(template_path))
    splice(buffered, plain, ansi)
  end

  def template_path
    File.expand_path("../../templates/intent-screen.md", __dir__)
  end

  # D16: replace the plain render's own text wherever it sits in the buffered
  # message, keeping everything after it verbatim. Falls back to a line-based
  # boundary (the "## ▶ " line through the last line starting with "|") only
  # when the buffered text does not start with the plain render exactly (the
  # model reformatted something) — the fallback also has to work for a
  # checklist-less intent, whose only Steps row is "| | | no steps yet |".
  def splice(buffered, plain, ansi)
    suffix =
      if buffered.start_with?(plain)
        buffered[plain.length..]
      else
        line_based_suffix(buffered)
      end
    return buffered if suffix.nil?

    "#{ansi.rstrip}\n\n#{suffix}"
  end

  def line_based_suffix(buffered)
    lines = buffered.lines
    start_idx = lines.index { |l| l.start_with?("## ▶ ") }
    return nil unless start_idx

    last_pipe_idx = nil
    lines.each_with_index do |l, i|
      last_pipe_idx = i if i > start_idx && l.start_with?("|")
    end
    return nil unless last_pipe_idx

    lines[(last_pipe_idx + 1)..].join
  end

  # O5: candidates are every discovered store holding a "<id>--*" directory.
  # A single candidate resolves outright (no ambiguity to break). With two or
  # more, the store whose project root is a path prefix of the payload's cwd
  # decides; if that narrows to anything other than exactly one, pass through
  # rather than guess (matrix 36).
  #
  # "cwd is a path prefix" is checked against the project's REAL checkout
  # path (projects.yml's own `path:`, e.g. ~/apps/personal/plastic) — never
  # against StoreDiscovery's `root` (~/.plastic/projects/<slug>, which only
  # holds INDEX.md and store/). Those are two different directories; a real
  # session's cwd lives under the former, never the latter. The global store
  # has no such checkout path, so it never wins by cwd — only by being the
  # sole candidate.
  def resolve_intent_dir(id, cwd)
    pattern = "#{glob_escape(id)}--*"
    candidates = StoreDiscovery.discover(@plastic_home)[:stores].filter_map do |s|
      dir = Dir.glob(File.join(s[:store], pattern)).find { |d| File.directory?(d) }
      dir && { slug: s[:slug], root: s[:root], intent_dir: dir }
    end
    return nil if candidates.empty?
    return candidates.first if candidates.length == 1

    registered = StoreProvisioning.load_projects(@plastic_home)
    cwd_matches = candidates.select do |c|
      real_path = registered.dig(c[:slug], "path")
      real_path && (cwd == real_path || cwd.start_with?("#{real_path}#{File::SEPARATOR}"))
    end
    return cwd_matches.first if cwd_matches.length == 1

    nil
  end

  # A recognized id should just be [A-Za-z0-9]+, but the id comes out of the
  # assistant's own streamed text, not a trusted schema — escape glob
  # metacharacters rather than assume it is well-formed.
  def glob_escape(str)
    str.gsub(/([*?\[\]{}])/) { "\\#{Regexp.last_match(1)}" }
  end

  def prune_old_buffers
    root = File.join(@tmp_root, BUFFER_DIR_NAME)
    return unless File.directory?(root)

    Dir.children(root).each do |session_dir|
      full = File.join(root, session_dir)
      next unless File.directory?(full)

      age = @now.to_i - File.mtime(full).to_i
      FileUtils.rm_rf(full) if age > BUFFER_MAX_AGE_SECONDS
    end
  rescue StandardError
    nil
  end
end
