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
# heading or EOF, the same slicing GraphRebuild.relocated_block uses), and a file
# WITHOUT a `## Links` gets one appended at end-of-body, separated by exactly one
# blank line, preserving the body's trailing-newline shape.
#
# Frontmatter is NEVER touched: the leading `---`...`---` block is preserved
# byte-for-byte and only the body is rebuilt.
module LinksSection
  module_function

  HEADING = "## Links"

  # PURE. Replace (or insert) the `## Links` section in `content` with
  # `section_text` (the canonical block from LinksProjection.section, which begins
  # with the `## Links` heading line and ends with a single trailing newline).
  # Returns the new content, or the original when nothing changed.
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

  # Rewrite ONLY the `## Links` section within the body text.
  def rewrite_body(body, section_text)
    if links_heading?(body)
      replace_section(body, section_text)
    else
      insert_section(body, section_text)
    end
  end

  # True iff the body has a top-level `## Links` heading line.
  def links_heading?(body)
    body.to_s.lines.any? { |l| l.rstrip == HEADING }
  end

  # Replace the existing `## Links` section (heading through the next top-level
  # `## ` heading or EOF) with `section_text`, preserving everything before the
  # heading and after the section byte-for-byte.
  def replace_section(body, section_text)
    lines = body.lines
    start = lines.index { |l| l.rstrip == HEADING }
    return body if start.nil?

    rest = lines[(start + 1)..] || []
    stop_rel = rest.index { |l| l.start_with?("## ") }
    tail = stop_rel ? rest[stop_rel..] : []

    before = lines[0...start].join
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
end
