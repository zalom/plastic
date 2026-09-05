# encoding: UTF-8
# frozen_string_literal: true

require "fileutils"
require_relative "screen_paint"

# MessageDisplay (intent 316a, O4/O5, round 3 concurrency fix) - the Claude
# Code MessageDisplay hook handler. One process per streamed chunk of every
# assistant message (D11), so it must be cheap and decide fast. Pure: every
# dependency (tmp_root, plastic_home, color, now, wait_ms, poll_ms, sleeper)
# is a constructor argument, never an ENV read, a Dir.pwd/Dir.home read, or
# the real Time.now/Kernel#sleep — the thin CLI (scripts/hook-message-display)
# is the one place allowed to read any of those.
#
# Claude adapter: Claude Code only; the core is harness-agnostic. (intent
# 316a1, D3 supersedes 316a's D6.) This is the sole caller that asks
# IntentScreenAnsi.render for `markdown_safe: true` (scripts/lib/
# intent_screen_ansi.rb) — see `finalize` below for why.
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
#
# Intent 331a: engagement is late-capable. A chunk carrying a screen opener
# engages the message from that chunk on, whatever its own index - not only
# chunk 0. Chunks before it pass through untouched (they already reached the
# terminal live, via the ordinary passthrough path). The engaging chunk
# returns the text before the opener as its displayContent and buffers the
# opener onward at its OWN index; SCREEN now carries that index (a decimal
# integer, not an empty marker) so the final chunk - a separate process in
# production - knows where to start waiting and splicing (D3/D6), and so
# NOSCREEN, no longer a final answer (D2), can be replaced once a later
# chunk engages. A fence line immediately wrapping the opener is dropped
# (D4): a lone fence in the engaging chunk's own prefix, and a lone closing
# fence right after the painted region in `finalize`. Neither ever reaches
# back into an earlier, already-displayed chunk.
class MessageDisplay
  # 317a (A4): engagement is grammar, not identity - any screen-family
  # opener engages, with NO intent-id resolution (the roster and delay
  # screens have none to resolve). ScreenPaint owns the full grammar. Used
  # per LINE (331a), not only against the start of a whole delta: a chunk's
  # own text is scanned line by line for the first line that opens a screen,
  # wherever it falls.
  ENGAGE_RE = /\A(?:##? )?[▶✔] /.freeze
  # 331a (D4): a lone fence line, opening (optional info string) or closing
  # (never one), by itself on its own line.
  FENCE_OPEN_RE = /\A```[^\n]*\z/.freeze
  FENCE_CLOSE_RE = /\A```\z/.freeze
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
  # message: does ITS OWN delta carry an opener anywhere (331a; used to be
  # only at the very start)? No opener writes NOSCREEN so every later chunk
  # can decide instantly rather than waiting out its own budget for a
  # decision that will never arrive - but NOSCREEN is no longer final (D2):
  # a later chunk carrying an opener still replaces it.
  def handle_chunk_zero(dir, delta, _cwd, final)
    split = split_at_opener(delta)
    unless split
      write_noscreen(dir)
      return nil
    end

    engage(dir, 0, split, final)
  end

  # A later chunk (index > 0) tests its OWN delta for an opener FIRST,
  # before consulting any existing decision (331a, D2): an opener engages
  # the message whatever the current decision says, including when NOSCREEN
  # is already on disk. Only once its own delta carries no opener does it
  # fall back to the original decision-driven wait.
  def handle_later_chunk(dir, index, delta, final)
    split = split_at_opener(delta)
    return engage(dir, index, split, final) if split

    decision = wait_for_decision(dir, gate_delta: final ? nil : delta)

    return nil unless decision == :screen

    write_chunk(dir, index, delta)
    final ? finalize_final(dir, index) : ""
  end

  # Engages the message starting at THIS chunk (whatever its index): writes
  # SCREEN carrying this chunk's index (replacing any NOSCREEN, D2/D6),
  # buffers the opener onward at this chunk's own index, and returns the
  # text before the opener (fence-stripped, D4) as the displayContent. When
  # this chunk is also final, the prefix is prepended to whatever `finalize`
  # produces (painted, or the buffered original on a fail-open) rather than
  # dropped.
  def engage(dir, index, split, final)
    prefix, rest = split
    prefix = strip_preceding_fence(prefix)
    write_screen(dir, index)
    remove_noscreen(dir)
    write_chunk(dir, index, rest)

    return prefix unless final

    finalized = finalize_final(dir, index)
    prefix.empty? ? finalized : "#{prefix}#{finalized}"
  end

  # Scans `delta` line by line for the first line that opens a screen
  # (331a: an opener can fall anywhere in a chunk's own delta, not only at
  # its start). Returns [prefix, rest] - the text before that line, and the
  # line onward - or nil when no line in this delta engages.
  def split_at_opener(delta)
    lines = delta.each_line.to_a
    idx = lines.index { |line| ENGAGE_RE.match?(line.sub(/\A[ \t]+/, "")) }
    return nil unless idx

    [lines[0...idx].join, lines[idx..].join]
  end

  # 331a (D4): a lone fence line immediately preceding the opener, inside
  # THIS SAME chunk's own prefix, is dropped - it never reaches the screen
  # (it would otherwise print directly above the painted block). A fence in
  # an earlier chunk is never touched: it was already displayed, verbatim,
  # by that earlier chunk's own return value.
  def strip_preceding_fence(prefix)
    lines = prefix.each_line.to_a
    return prefix if lines.empty?
    return prefix unless FENCE_OPEN_RE.match?(lines.last.strip)

    lines[0...-1].join
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

  # 331a (M5a): the start index crosses process boundaries through SCREEN's
  # own content, never in-memory state - the final chunk is routinely a
  # SEPARATE process from the one that engaged. An empty or missing file
  # reads back as 0 (chunk 0 engaged, today's shape, so nothing that ever
  # wrote an empty SCREEN breaks).
  def read_start_index(dir)
    path = File.join(dir, SCREEN_FILE)
    return 0 unless File.exist?(path)

    File.read(path).to_i
  rescue StandardError
    0
  end

  # Cheap, local, no file I/O: could this chunk's own delta plausibly be
  # part of an intent screen (ignoring leading whitespace)? Every chunk of
  # every ordinary prose message answers no, at zero cost.
  def maybe_screen?(delta)
    stripped = delta.lstrip
    stripped.empty? || stripped.start_with?("|") || stripped.start_with?("**")
  end

  # The final chunk additionally waits (same budget) for every chunk file
  # from the start index onward to exist before it reassembles and splices
  # (331a, D3/M5: from the start index, not from 0 - chunks before the
  # engaging one were never buffered at all, so waiting for them would only
  # ever burn the whole budget for files that will never appear). On
  # timeout it proceeds anyway with whatever is there (matrix, lead's
  # guard): never nil, never swallowed.
  def finalize_final(dir, index)
    start_index = read_start_index(dir)
    wait_for_chunk_files(dir, start_index, index)

    buffered = nil
    begin
      buffered = read_buffered_chunks(dir, start_index, index)
      finalize(buffered, nil)
    rescue StandardError
      # A read failing inside the assignment above leaves `buffered` at its
      # nil default (the assignment never completes), which the review pass
      # caught: D8/D10 promise the buffered original on any finalize
      # failure, never nil, once chunks were blanked. `||=` covers exactly
      # that gap without touching the ordinary case (buffered already holds
      # the real chunks read before `finalize` itself raised).
      buffered ||= ""
    ensure
      FileUtils.rm_rf(dir)
    end
  end

  def wait_for_chunk_files(dir, start_index, index)
    return if index <= start_index

    needed = (start_index...index).map(&:to_s)
    max_polls_for_budget.times do
      return if needed.all? { |n| File.exist?(File.join(dir, n)) }

      @sleeper.call(@poll_ms / 1000.0)
    end
  end

  def max_polls_for_budget
    return 0 unless @poll_ms.to_f.positive?

    (@wait_ms / @poll_ms.to_f).ceil
  end

  # Whatever chunk files exist FROM THE START INDEX onward, in index order,
  # concatenated -- gaps (a chunk that never arrived, or arrived too late)
  # are skipped rather than blocking reassembly (lead's guard: never return
  # nothing).
  def read_buffered_chunks(dir, start_index, index)
    (start_index..index).filter_map do |i|
      path = File.join(dir, i.to_s)
      File.exist?(path) ? File.read(path) : nil
    end.join
  end

  # 317a (D1/B10): paint what was printed. The buffered message's screen
  # region - located and bounded by ScreenPaint's own grammar - is re-laid in
  # the ANSI vocabulary; prose before and after survives verbatim. A region
  # the painter cannot parse returns the buffered original (A3: chunks were
  # already blanked, so nil here would truncate the message to its final
  # delta; nil is only for the never-engaged path in handle).
  #
  # markdown_safe: true (intent 316a1, D5) - Claude Code still Markdown-
  # processes displayContent even inside a raw ANSI block, so the Claude
  # adapter asks the harness-agnostic core to strip markdown noise. A harness
  # whose display surface passes raw ANSI through untouched would ask for
  # false instead.
  def finalize(buffered, _decision)
    lines = buffered.lines
    start = lines.index { |l| ScreenPaint.classify(l) == :opener }
    return buffered unless start

    region_stop = ScreenPaint.region_end(lines, start)
    painted = ScreenPaint.paint(lines[start...region_stop].join, color: true, markdown_safe: true)
    return buffered unless painted

    # 331a (D4): a lone CLOSING fence immediately after the painted region is
    # dropped - never the painting boundary itself (region_stop, used above,
    # is untouched), only where the suffix starts. An unrelated fenced code
    # block further down, with prose or a blank line between it and the
    # region, is never adjacent, so it always survives verbatim (M8b); a
    # closing fence never carries an info string, so an adjacent OPENING
    # fence of a real code block (which usually does) is never mistaken for
    # it either.
    suffix_start = region_stop
    suffix_start += 1 if suffix_start < lines.length && FENCE_CLOSE_RE.match?(lines[suffix_start].strip)

    suffix = lines[suffix_start..].to_a.join.sub(/\A\n+/, "")
    out = +"#{lines[0...start].join}#{painted.rstrip}\n"
    out << "\n#{suffix}" unless suffix.empty?
    out
  end

  def write_chunk(dir, index, delta)
    atomic_write(File.join(dir, index.to_s), delta)
  end

  # SCREEN's content is the engaging chunk's own index, as a decimal integer
  # (331a, D6) - read back by `read_start_index` so the final chunk (a
  # separate process, in production) knows where to start waiting and
  # splicing, and so `finalize_final` never touches chunks that were passed
  # through untouched before engagement.
  def write_screen(dir, index)
    atomic_write(File.join(dir, SCREEN_FILE), "#{index}\n")
  end

  def write_noscreen(dir)
    atomic_write(File.join(dir, NOSCREEN_FILE), "")
  end

  # 331a (D2/D6): NOSCREEN is no longer a final answer - a later chunk that
  # engages replaces it with SCREEN and, for safety, removes NOSCREEN so a
  # stale marker can never be read back once the real decision exists.
  def remove_noscreen(dir)
    FileUtils.rm_f(File.join(dir, NOSCREEN_FILE))
  end

  def atomic_write(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    tmp_path = "#{path}.tmp#{Process.pid}-#{rand(1_000_000)}"
    File.write(tmp_path, content)
    File.rename(tmp_path, path)
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
