# encoding: UTF-8
# frozen_string_literal: true

require "fileutils"
require_relative "intent_screen"
require_relative "intent_screen_ansi"
require_relative "store_discovery"
require_relative "store_provisioning"

# MessageDisplay (intent 316a, O4/O5, round 3 concurrency fix) - the Claude
# Code MessageDisplay hook handler. One process per streamed chunk of every
# assistant message (D11), so it must be cheap and decide fast. Pure: every
# dependency (tmp_root, plastic_home, color, now, wait_ms, poll_ms, sleeper)
# is a constructor argument, never an ENV read, a Dir.pwd/Dir.home read, or
# the real Time.now/Kernel#sleep — the thin CLI (scripts/hook-message-display)
# is the one place allowed to read any of those.
#
# A live run under a real pty (round 3) found that Claude Code fires the
# per-chunk hook processes CONCURRENTLY, not strictly in order. Chunk 0 is
# the one that recognizes the screen and creates the buffer (D13), and it can
# lose the race to chunks with a higher index: they would find no buffer yet
# and pass their raw Markdown straight through, producing a half plain /
# half styled screen. This class now survives that:
#
#   - One file per chunk (index-named), written atomically (temp name in the
#     same directory, then File.rename), so reassembly never depends on
#     arrival order — only on the index each chunk already carries.
#   - A decision file written BEFORE anything slow: chunk 0 writes SCREEN
#     (the resolved intent dir + store root) the moment it engages, or
#     NOSCREEN the moment it does not, so later chunks can decide without
#     redoing any of chunk 0's work.
#   - A later chunk asks a cheap, local question before ever waiting: could
#     this delta plausibly be part of a screen (leading "|", "**Steps**", or
#     blank)? An ordinary prose chunk arriving before SCREEN/NOSCREEN exists
#     passes through at once, at zero cost. A chunk shaped like part of a
#     screen polls for the decision, bounded (wait_ms/poll_ms), then fails
#     open. The final chunk always waits for the decision, whatever its own
#     shape, since it is the one that must not race — and it additionally
#     waits (same budget) for every earlier chunk file to exist before it
#     splices, returning whatever it does have rather than nothing when the
#     budget runs out.
#
# Protocol (D13, preserved): chunk 0 still decides, once, before anything is
# buffered or blanked. D10 (any failure while finalizing returns the
# buffered original, never nil, never "") and D12 (color: false never
# buffers or blanks anything) are unchanged.
class MessageDisplay
  MARKER_RE = /\A## ▶ (\S+) · /.freeze
  BUFFER_DIR_NAME = "plastic-message-display"
  BUFFER_MAX_AGE_SECONDS = 3600
  SCREEN_FILE = "SCREEN"
  NOSCREEN_FILE = "NOSCREEN"

  def initialize(tmp_root:, plastic_home:, color:, now:, wait_ms: 300, poll_ms: 20,
                 sleeper: ->(seconds) { sleep(seconds) })
    @tmp_root = tmp_root
    @plastic_home = plastic_home
    @color = color
    @now = now
    @wait_ms = wait_ms
    @poll_ms = poll_ms
    @sleeper = sleeper
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

    dir = self.class.buffer_path(tmp_root: @tmp_root, session_id: session_id, message_id: message_id)

    if index == 0
      handle_chunk_zero(dir, delta, cwd, final)
    else
      handle_later_chunk(dir, index, delta, final)
    end
  end

  # The message directory both this class and the bash launcher (hooks/
  # message-display) must agree on byte for byte (matrix 40): the launcher
  # checks this exact path's existence to decide whether chunk > 0 of an
  # engaged message gets handed to Ruby at all.
  def self.buffer_path(tmp_root:, session_id:, message_id:)
    File.join(tmp_root, BUFFER_DIR_NAME, session_id, message_id)
  end

  def self.chunk_path(tmp_root:, session_id:, message_id:, index:)
    File.join(buffer_path(tmp_root: tmp_root, session_id: session_id, message_id: message_id), index.to_s)
  end

  def self.screen_path(tmp_root:, session_id:, message_id:)
    File.join(buffer_path(tmp_root: tmp_root, session_id: session_id, message_id: message_id), SCREEN_FILE)
  end

  def self.noscreen_path(tmp_root:, session_id:, message_id:)
    File.join(buffer_path(tmp_root: tmp_root, session_id: session_id, message_id: message_id), NOSCREEN_FILE)
  end

  private

  # Chunk 0 decides, synchronously, before anything else touches this
  # message: recognize the marker (after leading whitespace only) AND
  # resolve the id, both before anything is buffered or blanked (F4). Either
  # failure writes NOSCREEN so every later chunk can decide instantly rather
  # than waiting out its own budget for a decision that will never arrive.
  def handle_chunk_zero(dir, delta, cwd, final)
    stripped = delta.sub(/\A[ \t]+/, "")
    m = stripped.match(MARKER_RE)
    resolved = m && resolve_intent_dir(m[1], cwd)

    unless resolved
      write_noscreen(dir)
      return nil
    end

    write_screen(dir, resolved)
    write_chunk(dir, 0, delta)
    final ? finalize_final(dir, 0) : ""
  end

  # A later chunk (index > 0) never redoes chunk 0's work: it only asks
  # whether a decision already exists, waiting for one (bounded) when it
  # does not and the chunk looks like it could matter. The final chunk
  # always waits for the decision regardless of its own shape.
  def handle_later_chunk(dir, index, delta, final)
    decision = wait_for_decision(dir, gate_delta: final ? nil : delta)

    return nil unless decision == :screen

    write_chunk(dir, index, delta)
    final ? finalize_final(dir, index) : ""
  end

  # Checks for an existing decision first (free) and only pays the cheap
  # shape test, then the bounded poll, when neither SCREEN nor NOSCREEN is
  # there yet. `gate_delta: nil` (the final chunk) skips the shape test
  # entirely and always polls for the decision.
  def wait_for_decision(dir, gate_delta:)
    decision = read_decision_now(dir)
    return decision if decision

    return :timeout if gate_delta && !maybe_screen?(gate_delta)

    max_polls_for_budget.times do
      @sleeper.call(@poll_ms / 1000.0)
      decision = read_decision_now(dir)
      return decision if decision
    end

    :timeout
  end

  def read_decision_now(dir)
    return :screen if File.exist?(File.join(dir, SCREEN_FILE))
    return :noscreen if File.exist?(File.join(dir, NOSCREEN_FILE))

    nil
  end

  # Cheap, local, no file I/O: could this chunk's own delta plausibly be
  # part of an intent screen (ignoring leading whitespace)? Every chunk of
  # every ordinary prose message answers no, at zero cost.
  def maybe_screen?(delta)
    stripped = delta.lstrip
    stripped.empty? || stripped.start_with?("|") || stripped.start_with?("**Steps**")
  end

  # The final chunk additionally waits (same budget) for every earlier chunk
  # file to exist before it reassembles and splices. On timeout it proceeds
  # anyway with whatever is there (matrix, lead's guard): never nil, never
  # swallowed.
  def finalize_final(dir, index)
    wait_for_chunk_files(dir, index)

    buffered = nil
    begin
      buffered = read_buffered_chunks(dir, index)
      decision = read_screen_decision(dir)
      finalize(buffered, decision)
    rescue StandardError
      buffered
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  def wait_for_chunk_files(dir, index)
    return if index <= 0

    needed = (0...index).map(&:to_s)
    max_polls_for_budget.times do
      return if needed.all? { |n| File.exist?(File.join(dir, n)) }

      @sleeper.call(@poll_ms / 1000.0)
    end
  end

  def max_polls_for_budget
    return 0 unless @poll_ms.to_f.positive?

    (@wait_ms / @poll_ms.to_f).ceil
  end

  # Whatever chunk files exist, in index order, concatenated -- gaps (a
  # chunk that never arrived, or arrived too late) are skipped rather than
  # blocking reassembly (lead's guard: never return nothing).
  def read_buffered_chunks(dir, index)
    (0..index).filter_map do |i|
      path = File.join(dir, i.to_s)
      File.exist?(path) ? File.read(path) : nil
    end.join
  end

  def read_screen_decision(dir)
    content = File.read(File.join(dir, SCREEN_FILE))
    intent_dir, store_root = content.split("\n")
    { intent_dir: intent_dir, store_root: store_root }
  end

  def finalize(buffered, decision)
    intent_dir = decision[:intent_dir]
    store_root = decision[:store_root]
    ansi = IntentScreenAnsi.render(intent_dir: intent_dir, store_root: store_root, color: true)
    plain = IntentScreen.render(intent_dir: intent_dir, store_root: store_root, template: File.read(template_path))
    splice(buffered, plain, ansi)
  end

  def template_path
    File.expand_path("../../templates/intent-screen.md", __dir__)
  end

  def write_chunk(dir, index, delta)
    atomic_write(File.join(dir, index.to_s), delta)
  end

  # IntentScreen/IntentScreenAnsi's store_root: is the TIER root (what HOLDS
  # store/ — e.g. .../projects/<slug> or plastic_home itself), never the
  # store/ directory itself; resolve_intent_dir's `root:` is already that.
  def write_screen(dir, resolved)
    atomic_write(File.join(dir, SCREEN_FILE), "#{resolved[:intent_dir]}\n#{resolved[:root]}\n")
  end

  def write_noscreen(dir)
    atomic_write(File.join(dir, NOSCREEN_FILE), "")
  end

  def atomic_write(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    tmp_path = "#{path}.tmp#{Process.pid}-#{rand(1_000_000)}"
    File.write(tmp_path, content)
    File.rename(tmp_path, path)
  end

  # D16: replace the plain render's own text wherever it sits in the buffered
  # message, keeping everything after it verbatim. Falls back to a line-based
  # boundary (the "## ▶ " line through the last line starting with "|") only
  # when the buffered text does not start with the plain render exactly (the
  # model reformatted something, or a chunk gap broke the exact match) — the
  # fallback also has to work for a checklist-less intent, whose only Steps
  # row is "| | | no steps yet |".
  def splice(buffered, plain, ansi)
    suffix =
      if buffered.start_with?(plain)
        buffered[plain.length..]
      else
        line_based_suffix(buffered, plain)
      end
    return buffered if suffix.nil?

    "#{ansi.rstrip}\n\n#{suffix}"
  end

  # Bounded fallback (matrix, lead's B1): walk forward from the "## ▶ " line
  # only through the screen's OWN contiguous run of blank lines, "|"-prefixed
  # table rows and the "**Steps**" heading, and stop at the first line that is
  # none of those. The boundary is the last "|" line seen before that stop —
  # never the last "|" line anywhere in the message. Scanning to the end
  # unbounded (the old behavior) swallows any prose the model wrote between
  # the screen and an unrelated Markdown table further down (a real hazard:
  # Plastic replies carry tables often).
  def line_based_suffix(buffered, plain)
    lines = buffered.lines
    start_idx = lines.index { |l| l.start_with?("## ▶ ") }
    return nil unless start_idx

    last_pipe_idx = nil
    i = start_idx + 1
    while i < lines.length
      line = lines[i]
      stripped = line.strip
      break unless stripped.empty? || line.start_with?("|") || stripped == "**Steps**"

      last_pipe_idx = i if line.start_with?("|")
      i += 1
    end
    return nil unless last_pipe_idx

    # Guard: never let the bounded scan consume more lines than the freshly
    # rendered plain screen itself has. If it would, something about the
    # buffered text does not match the shape splice() expects at all — pass
    # the original through rather than risk eating real prose.
    consumed = last_pipe_idx + 1 - start_idx
    return nil if consumed > plain.lines.length

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
