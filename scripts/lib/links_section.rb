# encoding: UTF-8
# frozen_string_literal: true

require_relative "intent_validator"

# LinksSection — pure, minimal, style-preserving rewrite of ONLY the `## Links`
# section of an intent file's content string (intent 72). Mirrors the discipline of
# FrontmatterWriter: pure (no file IO, no eval, no global/ENV state), and returns
# the original content UNCHANGED when nothing changed (idempotency).
#
# `## Links` is canonically the LAST sanctioned section
# (IntentValidator::SANCTIONED_SECTIONS = Intent, Context, Outcome, Insights,
# Links), and real intents put it last. So a file with an existing `## Links` has
# its section replaced in place (from the heading to the next top-level `## `
# heading or EOF), and a file WITHOUT a `## Links` gets one appended at end-of-body,
# separated by exactly one blank line, preserving the body's trailing-newline shape.
#
# FENCE AWARENESS (intent 72 corruption fix): a `## Links` heading INSIDE a fenced
# code block (``` or ~~~, possibly with an info string like ```markdown) is part of
# an EXAMPLE, not a real section. All section scanning here IGNORES headings inside
# fences and only ever targets the REAL `## Links` section (outside any fence). The
# section end is the next `## ` heading that is ALSO outside a fence, so a replace
# never consumes or unbalances a code fence. If more than one REAL `## Links`
# heading exists, #rewrite raises AmbiguousLinks rather than guess.
#
# Frontmatter is NEVER touched: the leading `---`...`---` block is preserved
# byte-for-byte and only the body is rebuilt.
module LinksSection
  module_function

  HEADING = "## Links"

  # A fence delimiter: ``` or ~~~ (any length >= 3), optional leading whitespace,
  # optional info string (e.g. ```markdown). Mirrors CommonMark fenced-code rules
  # closely enough for intent bodies.
  FENCE_RE = /\A\s*(`{3,}|~{3,})/

  # Raised when a body has more than one REAL `## Links` heading outside any fence;
  # the tool must fail loud rather than guess which one to rewrite.
  class AmbiguousLinks < StandardError
    def initialize(count)
      super("found #{count} real `## Links` headings outside code fences; refusing to guess")
    end
  end

  # PURE. Replace (or insert) the REAL `## Links` section in `content` with
  # `section_text` (the canonical block from LinksProjection.section, which begins
  # with the `## Links` heading line and ends with a single trailing newline).
  # Returns the new content, or the original when nothing changed. Raises
  # AmbiguousLinks when more than one real `## Links` heading exists.
  def rewrite(content, section_text)
    return content unless content.is_a?(String)

    fm, body = split_frontmatter(content)
    new_body = rewrite_body(body, section_text)
    updated = "#{fm}#{new_body}"
    updated == content ? content : updated
  end

  # Split content into [frontmatter_with_delimiters, body]. When there is no
  # frontmatter block, the frontmatter part is "" and the whole content is the
  # body. The frontmatter part is preserved byte-for-byte by the caller.
  def split_frontmatter(content)
    return ["", content] unless content.start_with?("---")

    parts = content.split("---", 3)
    return ["", content] if parts.length < 3

    ["---#{parts[1]}---", parts[2]]
  end

  # Rewrite ONLY the REAL `## Links` section within the body text.
  def rewrite_body(body, section_text)
    bounds = links_bounds(body)
    if bounds
      replace_section(body, section_text, bounds)
    else
      insert_section(body, section_text)
    end
  end

  # PURE. Locate the REAL `## Links` section (fence-aware). Returns
  # [start_index, end_index] line indices into body.lines, where start_index is the
  # `## Links` heading line and end_index is the index of the next out-of-fence
  # `## ` heading (or lines.length at EOF). Returns nil when there is no real
  # `## Links` heading. Raises AmbiguousLinks when more than one exists.
  def links_bounds(body)
    lines = body.to_s.lines
    starts = real_links_heading_indices(lines)
    return nil if starts.empty?
    raise AmbiguousLinks, starts.length if starts.length > 1

    start = starts.first
    stop = next_out_of_fence_heading(lines, start + 1)
    [start, stop]
  end

  # PURE. Indices of every `## Links` heading line that is OUTSIDE any code fence.
  # Accepts a body String or an Array of lines.
  def real_links_heading_indices(body_or_lines)
    lines = body_or_lines.is_a?(Array) ? body_or_lines : body_or_lines.to_s.lines
    indices = []
    in_fence = false
    fence_marker = nil
    lines.each_with_index do |line, i|
      if (m = fence_open_close(line, in_fence, fence_marker))
        in_fence = m[:in_fence]
        fence_marker = m[:marker]
        next
      end
      indices << i if !in_fence && line.rstrip == HEADING
    end
    indices
  end

  # PURE. Index of the first `## ` heading at or after `from` that is OUTSIDE any
  # code fence. Returns lines.length when none (EOF). Fence state is recomputed
  # from the top so nested example fences after the real heading are respected.
  def next_out_of_fence_heading(lines, from)
    in_fence = false
    fence_marker = nil
    lines.each_with_index do |line, i|
      if (m = fence_open_close(line, in_fence, fence_marker))
        in_fence = m[:in_fence]
        fence_marker = m[:marker]
        next
      end
      return i if i >= from && !in_fence && line.start_with?("## ")
    end
    lines.length
  end

  # PURE. Given the current fence state, decide whether `line` is a fence delimiter
  # and return the new state, or nil when the line is not a fence delimiter.
  # An opening fence records its marker family (` or ~); a closing fence must use a
  # marker of the SAME family and carry no info string.
  def fence_open_close(line, in_fence, fence_marker)
    m = line.match(FENCE_RE)
    return nil unless m

    marker = m[1]
    family = marker[0] # "`" or "~"
    if in_fence
      # A closing fence uses the same family, length >= the opener, no info string.
      rest = line.sub(FENCE_RE, "").strip
      if family == fence_marker && rest.empty?
        { in_fence: false, marker: nil }
      else
        # A delimiter of the OTHER family (or an info-string line) inside a fence is
        # literal content, not a fence event.
        nil
      end
    else
      { in_fence: true, marker: family }
    end
  end

  # True iff the body has a REAL (out-of-fence) `## Links` heading. Used by callers
  # to classify regenerate-vs-add without re-deriving fence state.
  def links_heading?(body)
    !real_links_heading_indices(body.to_s.lines).empty?
  end

  # Replace the REAL `## Links` section (the [start, stop] line bounds) with
  # `section_text`, preserving everything before the heading and after the section
  # byte-for-byte (including any fenced example that lives BEFORE the real section).
  def replace_section(body, section_text, bounds)
    lines = body.lines
    start, stop = bounds
    before = lines[0...start].join
    tail = (lines[stop..] || [])

    # `section_text` already ends with exactly one newline. When there is trailing
    # content (another section follows), separate the block from it with one blank
    # line; otherwise the section ends the body.
    block = tail.empty? ? section_text : "#{section_text}\n"
    "#{before}#{block}#{tail.join}"
  end

  # Append a `## Links` section at end-of-body, after the last existing section,
  # separated by exactly one blank line, preserving the body's trailing newline.
  def insert_section(body, section_text)
    trimmed = body.to_s.sub(/\s+\z/, "")
    if trimmed.empty?
      # An empty body (no sections) just becomes the section.
      section_text
    else
      "#{trimmed}\n\n#{section_text}"
    end
  end

  # PURE. Extract the REAL `## Links` section text (fence-aware), normalized to the
  # canonical block shape the projection emits: heading line + entry lines + a
  # single trailing newline. Returns "" when there is no real section. Shared by
  # the IO shell's audit and the doctor drift check so all three agree on the
  # location. Raises AmbiguousLinks when more than one real heading exists.
  def extract_section(body)
    bounds = links_bounds(body)
    return "" if bounds.nil?

    start, stop = bounds
    lines = body.to_s.lines
    section = lines[(start + 1)...stop].join.sub(/\n+\z/, "\n")
    section = "" if section.strip.empty?
    "#{HEADING}\n#{section}"
  end
end
