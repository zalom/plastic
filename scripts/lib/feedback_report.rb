# encoding: UTF-8
# frozen_string_literal: true

require "cgi"
require "fileutils"

# FeedbackReport: deterministic, dependency-injected engine that turns a
# title and an agent-assembled markdown body into a redacted local report
# file plus a prefilled GitHub new-issue URL (intent 174).
#
# Constructor DI, no `eval`, no ENV reads, no globals, stdlib only. Pure
# methods (`redact`, `fill_version`, `slug_for`, `report_path`, `build_url`,
# `apply_cap`, `compose`) plus one explicit side-effecting `persist`. Mirrors
# the engine-in-lib shape of `scripts/lib/skill_lint.rb`: the `feedback-report`
# CLI is a thin wrapper, `test/feedback_report_test.rb` proves the engine
# hermetically against an injected `plastic_home` and a fixed `now`.
#
# Trust model: this class never sends anything anywhere. `compose` returns a
# Result carrying a local file path and a browser URL; only the human, in
# their own authenticated browser, submits it. There is no send method here
# and there must never be one (see skills/feedback/references/transport-and-privacy.md).
class FeedbackReport
  GITHUB_REPO = "zalom/plastic"
  CAP_BYTES = 7500

  Result = Struct.new(:report_path, :body, :url, :encoded_url_bytes, :truncated, :page_break_note, keyword_init: true)

  # Ordered [Regexp, replacement] pairs. Order matters: `sk-ant-` must be
  # tried before the shorter `sk-` pattern so the longer form wins, and the
  # generic key/value assignment pattern runs last as a catch-all so it does
  # not steal a match a more specific pattern would have redacted more
  # precisely. Each pattern replaces the matched secret span with
  # `[REDACTED]`; the assignment pattern keeps the key name and separator and
  # redacts only the value.
  REDACTIONS = [
    [/\bgh[posru]_[A-Za-z0-9]{20,}\b/, "[REDACTED]"],
    [/\bgithub_pat_[A-Za-z0-9_]{20,}\b/, "[REDACTED]"],
    [/\bsk-ant-[A-Za-z0-9\-]{20,}\b/, "[REDACTED]"],
    [/\bsk-[A-Za-z0-9]{20,}\b/, "[REDACTED]"],
    [/\bAKIA[0-9A-Z]{16}\b/, "[REDACTED]"],
    [/\bBearer\s+[A-Za-z0-9._\-]{20,}/, "[REDACTED]"],
    [/\bxox[baprs]-[A-Za-z0-9\-]{10,}/, "[REDACTED]"],
    [/\bAIza[0-9A-Za-z_\-]{35}\b/, "[REDACTED]"],
    [/-----BEGIN[ A-Z]*PRIVATE KEY-----[\s\S]*?-----END[ A-Z]*PRIVATE KEY-----/, "[REDACTED]"],
    [/\b(api[_-]?key|secret|token|password)\b(\s*[:=]\s*)\S+/i, '\1\2[REDACTED]'],
  ].freeze

  def initialize(plastic_home:, now: Time.now, github_repo: GITHUB_REPO, cap_bytes: CAP_BYTES)
    @plastic_home = plastic_home
    @now = now
    @github_repo = github_repo
    @cap_bytes = cap_bytes
  end

  # Apply every redaction pattern in order and return the cleaned string.
  def redact(text)
    REDACTIONS.reduce(text) { |acc, (pattern, replacement)| acc.gsub(pattern, replacement) }
  end

  # Replace the `{{plastic_version}}` token with the injected VERSION file's
  # content, or the literal string "unknown" when the file is absent.
  def fill_version(body)
    version_file = File.join(@plastic_home, "VERSION")
    version = File.exist?(version_file) ? File.read(version_file).strip : "unknown"
    body.gsub("{{plastic_version}}", version)
  end

  # Kebab-case a title: downcase, collapse any run of non [a-z0-9] into one
  # hyphen, trim leading/trailing hyphens, cap at ~50 chars. Empty input (or
  # a title with no alphanumerics) falls back to "feedback".
  def slug_for(title)
    slug = title.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
    slug = slug[0, 50].gsub(/-+\z/, "")
    slug.empty? ? "feedback" : slug
  end

  # `{plastic_home}/feedback/{YYYY-MM-DD}--{slug}.md`, first free path. A
  # same-day same-slug collision tries `--2`, `--3`, ... until a free name
  # is found. This only reads the filesystem to check for a collision; it
  # never writes (that is `persist`'s job).
  def report_path(title)
    dir = File.join(@plastic_home, "feedback")
    base = "#{@now.strftime('%Y-%m-%d')}--#{slug_for(title)}"

    candidate = File.join(dir, "#{base}.md")
    return candidate unless File.exist?(candidate)

    n = 2
    loop do
      candidate = File.join(dir, "#{base}--#{n}.md")
      return candidate unless File.exist?(candidate)

      n += 1
    end
  end

  # Build the prefilled GitHub new-issue URL. ONLY `title` and `body` params,
  # percent-encoded. No `template`, no `labels`.
  def build_url(title, body)
    enc = ->(s) { CGI.escape(s) }
    "https://github.com/#{@github_repo}/issues/new?title=#{enc.call(title)}&body=#{enc.call(body)}"
  end

  # If the full body fits under the byte cap once encoded, return it as-is.
  # Otherwise binary-search the largest prefix of the body that, plus an
  # honest end-marker naming the local (uncapped) report file, still fits,
  # and return that page-one body instead. Returns
  # [url, url_body, truncated, page_break_note].
  def apply_cap(title, redacted_body, path)
    full_url = build_url(title, redacted_body)
    return [full_url, redacted_body, false, nil] if full_url.bytesize <= @cap_bytes

    end_marker = "\n\n---\nFull report continues in your local file: #{path}\n" \
                 "Paste the rest below if relevant."

    lo = 0
    hi = redacted_body.length
    best_n = 0
    while lo <= hi
      mid = (lo + hi) / 2
      candidate_url = build_url(title, redacted_body[0...mid] + end_marker)
      if candidate_url.bytesize <= @cap_bytes
        best_n = mid
        lo = mid + 1
      else
        hi = mid - 1
      end
    end

    page_one = redacted_body[0...best_n] + end_marker
    final_url = build_url(title, page_one)
    raise "feedback report exceeds cap_bytes even at page one (#{final_url.bytesize} > #{@cap_bytes})" if final_url.bytesize > @cap_bytes

    [final_url, page_one, true, end_marker.strip]
  end

  # Orchestrate: redact the title, fill the version token and redact the
  # body, resolve the report path from the REDACTED title (so a secret in
  # the title never lands in the filename either), then cap the URL. The
  # title is redacted before it ever reaches build_url/apply_cap, so a
  # secret pasted into the title cannot ride the `title=` URL param
  # unredacted. The FULL redacted body always goes to disk; only the URL's
  # body may be the capped page-one.
  def compose(title:, body:)
    redacted_title = redact(title)
    filled = fill_version(body)
    redacted_body = redact(filled)
    path = report_path(redacted_title)
    url, _url_body, truncated, note = apply_cap(redacted_title, redacted_body, path)

    Result.new(
      report_path: path,
      body: redacted_body,
      url: url,
      encoded_url_bytes: url.bytesize,
      truncated: truncated,
      page_break_note: note
    )
  end

  # Write the FULL redacted body to disk. The only side-effecting method on
  # this class.
  def persist(result)
    FileUtils.mkdir_p(File.dirname(result.report_path))
    File.write(result.report_path, result.body)
    result
  end
end
