# encoding: UTF-8
# frozen_string_literal: true

require "date"
require "fileutils"
require_relative "store_provisioning"

# SessionLedger - the pure library behind the session intent day ledger (intent
# 297). It owns identity derivation (day id, short session id, project slug),
# the day and session path layout under a store's `.sessions/` and `.tmp/`
# directories, the byte-exact checklist and savepoint line formats, and the
# locked reads and writes that let many sessions share one day's files safely.
#
# Every method takes every path as an argument. This file reads no environment
# variable and runs no dynamically constructed code: only its CLIs
# (`scripts/new-intent --tmp`, `scripts/append-ledger`) read the environment
# and pass what they read in.
module SessionLedger
  # Raised by #set_state when an in-place edit cannot take an exclusive lock
  # (a filesystem without flock support). An append stays safe unlocked, since
  # a single O_APPEND write lands whole; an in-place byte edit does not, so it
  # refuses rather than risk a torn read-modify-write. The CLI maps this to
  # exit 3.
  class LockUnavailableError < StandardError; end

  module_function

  # --- Constants (spec D13), byte exact ------------------------------------

  SESSIONS_DIR = ".sessions"
  TMP_DIR = ".tmp"
  # Named here, not in a CLI, so a caller can reference the key without the
  # literal harness-branded env var name appearing in its own source (a few
  # scripts are guarded against naming a harness at all).
  SESSION_ID_ENV_KEY = "CLAUDE_CODE_SESSION_ID"
  DAY_ID = /\A\d{8}\z/
  EVENTS = %w[Item Done Note]
  STATES = { pending: "~", open: " ", done: "x", moved: ">", dropped: "-", promoted: "^" }.freeze

  # Project slugs and session tags are restricted to this character class
  # (spec D4). Used both to filter a slug read out of projects.yml
  # (#project_slug) and, by append-ledger, to validate an explicit --project.
  SLUG_RE = /\A[a-z0-9-]+\z/.freeze

  # Default lock strategy for #append_line and #set_state: a real flock call
  # on the handle. Tests inject a replacement lambda here (never a global or
  # an environment-variable flag, per the library's no-environment-read rule)
  # to simulate a SystemCallError from a filesystem without flock support,
  # proving the unlocked-append fallback and the LockUnavailableError -> exit
  # 3 mapping hermetically, with no need for a real flock-less filesystem.
  DEFAULT_FLOCK = ->(handle, mode) { handle.flock(mode) }
  private_constant :DEFAULT_FLOCK

  # The first append to checklist.md writes this header, then a blank line,
  # before any checklist content (spec D9). savepoint.md never gets a header.
  def checklist_header(day)
    "# Checklist: session ledger #{day}\n\n"
  end

  # --- Identity -------------------------------------------------------------

  # The day id is the caller's local wall-clock date. Never call `.utc` here:
  # the owner's day is his wall clock, and a UTC id would already read
  # tomorrow in the evening locally. Instants inside ledger lines stay UTC,
  # which is a concern of #savepoint_line, not this method.
  def day_id(now = Time.now)
    now.strftime("%Y%m%d")
  end

  # True iff `id` is eight digits that also parse as a real calendar date, so
  # a shape match like "20261340" (month 13) is still rejected.
  def valid_day_id?(id)
    s = id.to_s
    return false unless s.match?(DAY_ID)

    begin
      Date.strptime(s, "%Y%m%d")
      true
    rescue Date::Error, ArgumentError
      false
    end
  end

  # The first eight `[a-z0-9]` characters of the caller's session id, after
  # downcasing. Source order: `explicit`, then `env_id`, then the literal
  # `"local"`. Both candidates are arguments; only a CLI reads the environment.
  def short_session_id(explicit = nil, env_id = nil)
    candidate = [explicit, env_id].find { |c| c.is_a?(String) && !c.strip.empty? }
    candidate ||= "local"

    cleaned = candidate.downcase.gsub(/[^a-z0-9]/, "")
    cleaned = "local" if cleaned.empty?
    cleaned[0, 8]
  end

  # The slug of the registered `projects.yml` path that is the longest match
  # for `cwd` (equal to, or nested under, that path). Falls back to the
  # literal `"global"` when nothing matches: an invented slug (from a
  # directory basename) would name no real store. A candidate slug that does
  # not match SLUG_RE (spec D4: `[a-z0-9-]` only) is skipped rather than
  # returned, since it would corrupt a ledger line that embeds it verbatim;
  # the "global" fallback is always safe by construction.
  def project_slug(cwd, plastic_home:)
    expanded_cwd = File.expand_path(cwd)
    projects = StoreProvisioning.load_projects(plastic_home)
    return "global" unless projects.is_a?(Hash)

    matches = projects.filter_map do |slug, info|
      next unless info.is_a?(Hash)
      next unless slug.is_a?(String) && SLUG_RE.match?(slug)

      path = info["path"]
      next unless path

      root = File.expand_path(path)
      next unless expanded_cwd == root || expanded_cwd.start_with?(root + File::SEPARATOR)

      [root.length, slug]
    end

    best = matches.max_by { |(length, _slug)| length }
    best ? best[1] : "global"
  end

  # --- Day paths (no I/O) ----------------------------------------------------

  def sessions_root(store)
    File.join(store, SESSIONS_DIR)
  end

  def day_dir(store, day)
    File.join(sessions_root(store), day)
  end

  def day_file(store, day)
    File.join(day_dir(store, day), "#{day}.md")
  end

  def checklist_path(store, day)
    File.join(day_dir(store, day), "checklist.md")
  end

  def savepoint_path(store, day)
    File.join(day_dir(store, day), "savepoint.md")
  end

  # --- Session paths (no I/O except #ensure_tmp_root) ------------------------

  def tmp_root(store)
    File.join(store, TMP_DIR)
  end

  def session_tmp_dir(store, session_id)
    File.join(tmp_root(store), session_id)
  end

  def pointer_path(store, session_id)
    File.join(session_tmp_dir(store, session_id), "current")
  end

  def heartbeat_path(store, session_id)
    File.join(session_tmp_dir(store, session_id), "heartbeat")
  end

  # Create `.tmp/` plus a `.gitignore` holding exactly `*`, if that file does
  # not already exist. The store is a local git repo that auto-commits
  # `add -A`, so without this ignore file every heartbeat write would enter
  # git history. Intent 298 calls this before writing a pointer or heartbeat;
  # this intent only defines it. Returns the tmp root path.
  def ensure_tmp_root(store)
    root = tmp_root(store)
    FileUtils.mkdir_p(root)

    gitignore = File.join(root, ".gitignore")
    File.write(gitignore, "*\n") unless File.exist?(gitignore)

    root
  end

  # --- Lines ------------------------------------------------------------------

  # Collapse every run of whitespace (newlines included) to one space, strip,
  # then cap the result at 200 characters total, ending in "..." when the
  # input was longer. Returns an empty string when nothing survives; the
  # caller decides whether that is a usage error.
  def sanitize_summary(text)
    collapsed = text.to_s.gsub(/\s+/, " ").strip
    return collapsed if collapsed.length <= 200

    "#{collapsed[0, 197]}..."
  end

  # --- capture_worthy? (spec D2, D7; supersedes 298 D2(c)) -------------------

  # One complete top-level harness envelope tag block: "<name ...>...</name>".
  # Non-greedy (.*?) so sibling blocks are each matched on their own rather
  # than one match spanning from the first block's opening tag all the way to
  # the LAST block's closing tag (post-execution review item 3: an envelope
  # on both sides of real work, "<system-reminder>...</system-reminder>\nfix
  # the parser\n<task-notification>...</task-notification>", must not be
  # read as one giant envelope swallowing the work in the middle).
  ENVELOPE_BLOCK_RE = /<([A-Za-z][\w-]*)(?:\s[^>]*)?>.*?<\/\1>/m
  private_constant :ENVELOPE_BLOCK_RE

  # The whole prompt, case- and whitespace-insensitively, and nothing else
  # (rule 3, D2): a trigger word inside a longer real instruction ("continue
  # the dashboard fix and then release") must not match this.
  BARE_TRIGGERS = %w[continue auto].freeze
  private_constant :BARE_TRIGGERS

  # Words whose presence marks a prompt as actionable work (rule 4's escape
  # hatch, D2's accept bias). Deliberately excludes common nouns that also
  # read as everyday verbs in casual remarks (e.g. "release", "ship", "plan"):
  # including them would make ordinary conversation about a past release or
  # plan look like a work request. Matched with an optional inflection suffix
  # (post-execution review BLOCKER): the bare stems alone missed "fixed",
  # "updated", "added", "reviewed", "implemented" -- exactly the past-tense
  # and -ing forms real work summaries use.
  WORK_MARKER_WORDS = %w[
    fix add remove delete update upgrade implement write build create refactor
    debug investigate review test deploy commit merge revert rename configure
    install migrate document generate draft resolve help need want make change
    setup
  ].freeze
  private_constant :WORK_MARKER_WORDS

  WORK_MARKER_PHRASES = [
    "can you", "could you", "would you", "let's", "let us", "set up", "look into", "figure out",
  ].freeze
  private_constant :WORK_MARKER_PHRASES

  WORK_MARKER_RE = /\b(?:#{WORK_MARKER_WORDS.join("|")})(?:s|d|ed|ing)?\b/i
  private_constant :WORK_MARKER_RE

  # A first word that reads as an interrogative opener, checked case-
  # insensitively against the prompt's first whitespace-separated token.
  # Post-execution review BLOCKER: trimmed from the original, wider list
  # (which also carried "how", "when", "where", "was", "were", "do", "did",
  # "will", "shall", "should") down to words that open a genuine QUESTION at
  # least as often as an ordinary command or request. Measured against 43
  # invented and 27 real day-ledger prompts: the dropped words open ordinary
  # work requests ("do the release now...", "when you are done, tag the
  # release...", "will you push that branch...", "should I bump the version
  # files...") far more often than they open a bare question worth rejecting.
  QUESTION_STARTERS = %w[
    what why who whom whose which is are am does can could would
  ].freeze
  private_constant :QUESTION_STARTERS

  # A narrow set of retrospective-remark shapes ("that release went smoother
  # than the last one"): comparative or evaluative observations about how
  # something already went. Deliberately narrow (D2's accept bias): a broad
  # "any declarative sentence with no recognized verb" rule would also catch
  # ordinary work summaries like "harness text wins the pending line", which
  # must stay accepted.
  REMARK_PATTERNS = [
    /\bwent\s+\w+\s+than\b/i,
    /\bwent\s+(?:well|badly|smoothly|great|poorly|terribly)\b/i,
  ].freeze
  private_constant :REMARK_PATTERNS

  # True iff nothing but harness envelope tag block(s) -- and whitespace --
  # remain once every complete top-level block is stripped out. A prompt
  # that is one envelope alone, or several envelopes with no other content,
  # matches; a prompt carrying real work anywhere outside an envelope (before,
  # after, or between several of them) does not.
  def whole_prompt_envelope?(stripped)
    stripped.gsub(ENVELOPE_BLOCK_RE, "").strip.empty?
  end

  def bare_trigger?(stripped)
    BARE_TRIGGERS.include?(stripped.downcase)
  end

  def work_marker?(text)
    return true if WORK_MARKER_RE.match?(text)

    downcased = text.downcase
    WORK_MARKER_PHRASES.any? { |p| downcased.include?(p) }
  end

  def interrogative?(stripped)
    return true if stripped.end_with?("?")

    first_word = stripped.split(/\s+/).first.to_s.downcase.gsub(/[^a-z]/, "")
    QUESTION_STARTERS.include?(first_word)
  end

  def bare_remark?(stripped)
    REMARK_PATTERNS.any? { |re| re.match?(stripped) }
  end

  # Internal helpers only: #capture_worthy? is the sole public contract
  # (post-execution review item 9).
  private_class_method :whole_prompt_envelope?, :bare_trigger?, :work_marker?, :interrogative?, :bare_remark?

  # Whether `prompt` earns a pending checklist line (spec D2). Bias is
  # ACCEPT: this rejects only on four named rules -- the 10-char floor (on
  # its own collapsed copy), a whole-prompt harness envelope, a bare
  # continue/auto trigger, and an interrogative or bare-remark prompt
  # carrying no work marker -- and accepts everything else, including a
  # work-shaped question and an envelope followed by real work. Takes the
  # RAW prompt (not the sanitized/truncated line text) so rule 2 sees the
  # prompt's true first character and multi-line shape.
  def capture_worthy?(prompt)
    raw = prompt.to_s
    return false if sanitize_summary(raw).length < 10

    stripped = raw.strip
    return false if whole_prompt_envelope?(stripped)
    return false if bare_trigger?(stripped)
    return false if !work_marker?(stripped) && (interrogative?(stripped) || bare_remark?(stripped))

    true
  end

  # One LF-terminated checklist line, byte exact per spec D5. The state
  # marker is fixed width across all three states, which is what lets a later
  # promote or tick be a one-byte write at a known offset.
  def checklist_line(state, session, project, summary)
    marker = STATES.fetch(state) { raise ArgumentError, "unknown checklist state: #{state.inspect}" }
    "- [#{marker}] [#{session}] [#{project}] #{summary}\n"
  end

  # One LF-terminated savepoint line, byte exact per spec D5. Separators are
  # two spaces, so `split(/\s{2,}/)` yields exactly three parts. The
  # timestamp is UTC ISO 8601, matching every other savepoint line in the
  # store; the day id stays local wall clock, an intentional asymmetry.
  def savepoint_line(event, session, project, summary, now:)
    raise ArgumentError, "unknown savepoint event: #{event.inspect}" unless EVENTS.include?(event)

    timestamp = now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    "#{timestamp}  #{event}  [#{session}] [#{project}] #{summary}\n"
  end

  # The inverse of #checklist_line: parse a checklist line positionally (the
  # state marker, the first bracket group, the second bracket group, then the
  # rest as the summary), so a bracket typed inside a summary is never read
  # as a tag. Returns nil when the line does not match.
  CHECKLIST_LINE_RE = /\A- \[(.)\] \[([^\]]*)\] \[([^\]]*)\] (.*)\z/m.freeze
  private_constant :CHECKLIST_LINE_RE

  def parse_checklist_line(line)
    # #scrub replaces any invalid byte with U+FFFD so a stray non-UTF-8 byte
    # anywhere in checklist.md never raises ArgumentError out of the regex
    # match; it only ever affects that one line's parsed summary. Callers
    # that need byte-exact offsets (namely #set_state) must measure against
    # the UNSCRUBBED line, since #scrub can change a line's bytesize.
    match = CHECKLIST_LINE_RE.match(line.to_s.chomp.scrub)
    return nil unless match

    marker, session, project, summary = match.captures
    state = STATES.key(marker)
    return nil unless state

    { state: state, session: session, project: project, summary: summary }
  end

  # --- Token rendering (internal) --------------------------------------------

  # Block-form gsub, mirroring scripts/new-intent#render_tokens: a String
  # replacement argument reinterprets backslash sequences, so the block form
  # substitutes each value literally.
  def render_tokens(text, tokens)
    tokens.reduce(text) { |acc, (key, value)| acc.gsub("{{#{key}}}") { value.to_s } }
  end

  # --- Locked writes and reads (spec D8) --------------------------------------

  # Append `line` to `path`, taking an exclusive lock on the target file
  # itself (never a sibling lock file, never via a rename). Opens
  # WRONLY | APPEND | CREAT so a concurrent append always lands at the
  # current end of file. Once the lock is held, writes `header` first only
  # when the file is still size zero (the size check happens under the lock
  # on purpose: O_CREAT without O_EXCL hands every racer the same inode, so
  # the lock serializes them and exactly one racer sees size zero). Then
  # writes the full line in one call. Rescues SystemCallError from flock
  # only: on a filesystem without flock support, the append proceeds
  # unlocked, since a single O_APPEND write still lands whole there. Always
  # returns true.
  def append_line(path, line, header: nil, flock: DEFAULT_FLOCK)
    handle = File.open(path, File::WRONLY | File::APPEND | File::CREAT, 0o644)
    begin
      begin
        flock.call(handle, File::LOCK_EX)
      rescue SystemCallError
        nil
      end

      handle.write(header) if header && handle.size.zero?
      handle.write(line)
      # Flush explicitly before unlocking. MRI happens to flush a writable
      # handle's buffer as a side effect inside rb_file_flock, but that is
      # undocumented behavior, so flush on purpose rather than depend on it.
      handle.flush

      begin
        handle.flock(File::LOCK_UN)
      rescue SystemCallError
        nil
      end
    ensure
      handle.close
    end
    true
  end

  # Flip the newest line (last in file order) whose session tag equals
  # `session` and whose state equals `from` to `to`, narrowed to lines whose
  # summary contains `match` when given (spec D7). The lock is taken on the
  # target file itself. Once held, the file is scanned by byte offset, and
  # exactly one byte (the state marker, at the matched line's start offset
  # plus 3, past the "- [" prefix) is overwritten with `IO#pwrite`, so every
  # other byte in the file stays identical: this is exactly why the pending
  # marker is `[~]`, a fixed width shared with `[ ]` and `[x]`, rather than a
  # bare tilde.
  #
  # Identifying the target line and flipping it happen inside the SAME
  # LOCK_EX hold, on purpose: an earlier version identified the target under
  # a released LOCK_SH, in a separate call, then re-identified and flipped it
  # under a fresh LOCK_EX. Two concurrent promoters could both read the same
  # "newest pending" line before either flipped anything, each then flip a
  # DIFFERENT line under their own (correctly serialized) LOCK_EX, and the
  # caller's earlier lookup would go stale, naming the wrong line in a
  # --savepoint entry. Returning the flipped line's own summary from inside
  # this lock is what makes that identify-and-flip atomic, so a caller never
  # needs a second, separately-locked read to learn what it just changed.
  #
  # Returns the flipped line's summary (a String) when a byte changed, or nil
  # (writing nothing) when the file does not exist or nothing matches. Raises
  # LockUnavailableError, refusing to write at all, when the flock cannot be
  # taken (filesystem without flock support): unlike an append, an in-place
  # edit cannot fall back to unlocked, since a racing writer could tear the
  # read-modify-write. `flock:` is a test seam (see DEFAULT_FLOCK); production
  # callers never pass it.
  def set_state(path, from:, to:, session:, match: nil, flock: DEFAULT_FLOCK)
    return nil unless File.exist?(path)

    STATES.fetch(from)
    to_marker = STATES.fetch(to)

    handle = File.open(path, File::RDWR)
    locked = true
    begin
      flock.call(handle, File::LOCK_EX)
    rescue SystemCallError
      locked = false
    end

    unless locked
      handle.close
      raise LockUnavailableError, "cannot take an exclusive lock on #{path}"
    end

    begin
      content = handle.read
      target_offset = nil
      target_summary = nil
      offset = 0

      content.each_line do |raw_line|
        parsed = parse_checklist_line(raw_line)
        if parsed && (session.nil? || parsed[:session] == session) && parsed[:state] == from &&
           (match.nil? || parsed[:summary].include?(match))
          target_offset = offset + 3 # past the "- [" prefix
          target_summary = parsed[:summary]
        end
        # Accumulate over the UNSCRUBBED raw_line, never the copy
        # #parse_checklist_line scrubs internally for matching: #scrub can
        # change a line's bytesize, and pwrite below must land at the true
        # on-disk byte offset.
        offset += raw_line.bytesize
      end

      if target_offset.nil?
        nil
      else
        handle.pwrite(to_marker, target_offset)
        handle.flush
        target_summary
      end
    ensure
      begin
        handle.flock(File::LOCK_UN)
      rescue SystemCallError
        nil
      end
      handle.close
    end
  end

  # Flip every checklist line in state `from` to state `to` for one session
  # (or any session when `session` is nil), narrowed to summaries containing
  # `match` when given (intent 301). Same lock discipline as #set_state: one
  # LOCK_EX for the whole read-scan-write, one pwrite of one byte per
  # flipped line at its measured offset, never a whole-file rewrite, and a
  # LockUnavailableError rather than any unlocked write. Returns the count of
  # lines flipped, 0 when the file is absent or nothing matches.
  def flip_all(path, from:, to:, session: nil, match: nil, flock: DEFAULT_FLOCK)
    return 0 unless File.exist?(path)

    STATES.fetch(from)
    to_marker = STATES.fetch(to)
    handle = File.open(path, File::RDWR)
    locked = true
    begin
      flock.call(handle, File::LOCK_EX)
    rescue SystemCallError
      locked = false
    end
    unless locked
      handle.close
      raise LockUnavailableError, "cannot take an exclusive lock on #{path}"
    end

    begin
      content = handle.read
      offsets = []
      offset = 0
      content.each_line do |raw_line|
        parsed = parse_checklist_line(raw_line)
        if parsed && (session.nil? || parsed[:session] == session) && parsed[:state] == from &&
           (match.nil? || parsed[:summary].include?(match))
          offsets << offset + 3
        end
        offset += raw_line.bytesize
      end
      offsets.each { |o| handle.pwrite(to_marker, o) }
      handle.flush unless offsets.empty?
      offsets.size
    ensure
      begin
        handle.flock(File::LOCK_UN)
      rescue SystemCallError
        nil
      end
      handle.close
    end
  end

  # Read `path` under a shared lock, returning its content. Returns an empty
  # string when the file does not exist. Rescues SystemCallError from flock
  # and reads anyway.
  def read_locked(path)
    return "" unless File.exist?(path)

    handle = File.open(path, File::RDONLY)
    begin
      begin
        handle.flock(File::LOCK_SH)
      rescue SystemCallError
        nil
      end
      handle.read
    ensure
      begin
        handle.flock(File::LOCK_UN)
      rescue SystemCallError
        nil
      end
      handle.close
    end
  end

  # --- The day scaffold (spec D12) --------------------------------------------

  # The one and only scaffold implementation. `new-intent --tmp` is its CLI,
  # and `append-ledger` calls it directly on EVERY invocation (cheap and
  # idempotent, so there is no cheaper-but-wrong guard to key on instead), so
  # a capture that crosses midnight never fails and never needs a second
  # process. Creates exactly `<day>/<day>.md`: no checklist.md, no
  # savepoint.md, no actions/, no resources/. `checklist.md` and
  # `savepoint.md` come into existence on first append, written by
  # append-ledger under the lock, which is why this method never touches
  # them.
  #
  # Create versus join is decided by opening the day file with
  # File::CREAT | File::EXCL: the winner renders the template and returns
  # created: true; every loser, including a repair of a crashed
  # mid-scaffold with no md file yet, returns created: false without
  # changing a byte. DATE (the day's own calendar date, used in the `intent:`
  # line) is derived from `day`, not from `now`, so an explicit --day renders
  # its own date rather than today's; `now:` instead sources CREATED, the
  # `created:` frontmatter field, since that field records when the scaffold
  # FILE was actually written, which can differ from the day it is for (a
  # repair or a midnight-crossing capture can scaffold a past day's file
  # today). Defaults to Time.now; tests inject a fixed `now:` to make the
  # scaffold's `created:` value deterministic.
  #
  # If rendering fails partway (a missing or relocated templates dir, a bad
  # day), the file this call just created is unlinked before the error
  # re-raises, so no zero-byte or partial <day>.md is left behind to wedge
  # every later #open_day call onto the Errno::EEXIST "already exists"
  # branch with no file to repair.
  def open_day(store:, day:, templates:, author:, now: Time.now)
    dir = day_dir(store, day)
    FileUtils.mkdir_p(dir)

    file = day_file(store, day)
    handle = begin
      File.open(file, File::WRONLY | File::CREAT | File::EXCL, 0o644)
    rescue Errno::EEXIST
      nil
    end

    return { dir: dir, created: false } unless handle

    begin
      begin
        date = Date.strptime(day, "%Y%m%d").iso8601
        created = now.strftime("%Y-%m-%d")
        template = File.read(File.join(templates, "session-intent.md"))
        rendered = render_tokens(template, "DAY" => day, "DATE" => date, "CREATED" => created, "AUTHOR" => author)
        handle.write(rendered)
      rescue StandardError
        File.delete(file) if File.exist?(file)
        raise
      end
    ensure
      handle.close unless handle.closed?
    end

    { dir: dir, created: true }
  end
end
