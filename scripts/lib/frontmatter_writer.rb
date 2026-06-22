# encoding: UTF-8
# frozen_string_literal: true

# FrontmatterWriter — pure, minimal, style-preserving rewrite of the `sources:`
# and `chain:` arrays in an intent file's content string (intent 49).
#
# It rewrites ONLY those two arrays and leaves every other frontmatter line and
# the entire body byte-identical. It preserves each array's existing serialization
# style independently:
#   - flow style: `sources: ["40", "1a"]`  (or `[]`)
#   - block style: a `sources:` line followed by `  - '1a'` item lines
# When the desired array equals the file's current value (same ids, same order),
# the content is returned UNCHANGED so a re-run produces no diff (idempotency).
#
# Pure: no file IO, no eval, no global/ENV state. The IO shell reads/writes files.
module FrontmatterWriter
  module_function

  # Rewrite `sources:`/`chain:` in `content`. `sources`/`chain` are the desired
  # final arrays of id strings. Returns the new content (or the original when
  # nothing changed). Only operates within the leading `---`...`---` frontmatter
  # block; never touches the body.
  def rewrite_arrays(content, sources:, chain:)
    return content unless content.is_a?(String) && content.start_with?("---")

    parts = content.split("---", 3)
    return content if parts.length < 3

    fm = parts[1]
    body = parts[2]

    fm = rewrite_one(fm, "sources", sources)
    fm = rewrite_one(fm, "chain", chain)

    "---#{fm}---#{body}"
  end

  # Rewrite a single `key:` array within the frontmatter text `fm`, preserving the
  # key's existing flow-vs-block style. No-op when the key is absent or unchanged.
  def rewrite_one(fm, key, desired)
    lines = fm.lines
    idx = lines.index { |l| l.match?(/\A#{Regexp.escape(key)}:\s/) || l.match?(/\A#{Regexp.escape(key)}:\s*\z/) }
    return fm if idx.nil?

    header = lines[idx]
    if block_style?(lines, idx)
      rewrite_block(lines, idx, key, desired)
    else
      rewrite_flow(lines, idx, header, key, desired)
    end
  end

  # The key is block style when its own line carries no inline value and the next
  # non-blank line is a `-` list item.
  def block_style?(lines, idx)
    header = lines[idx]
    inline = header.sub(/\A[^:]+:/, "").strip
    return false unless inline.empty?

    nxt = lines[idx + 1]
    !nxt.nil? && nxt.match?(/\A\s*-\s/)
  end

  # Flow style: replace the inline array on the header line, preserving indentation
  # and any trailing newline. No-op when the current ids already match `desired`.
  def rewrite_flow(lines, idx, header, key, desired)
    current = parse_flow(header)
    return lines.join if current == desired

    newline = header.end_with?("\n") ? "\n" : ""
    lines[idx] = "#{key}: #{render_flow(desired)}#{newline}"
    lines.join
  end

  # Parse the inline flow array from a `key: [ ... ]` header line.
  def parse_flow(header)
    inline = header.sub(/\A[^:]+:/, "").strip
    return [] if inline.empty? || inline == "[]"

    inline = inline.sub(/\A\[/, "").sub(/\]\z/, "")
    inline.split(",").map { |t| t.strip.gsub(/\A['"]|['"]\z/, "") }.reject(&:empty?)
  end

  def render_flow(ids)
    return "[]" if ids.empty?

    "[#{ids.map { |i| "\"#{i}\"" }.join(", ")}]"
  end

  # Block style: replace the contiguous `-` item lines following the header. No-op
  # when the current ids already match `desired`. Preserves the item indentation
  # and quoting style sampled from the existing first item.
  def rewrite_block(lines, idx, key, desired)
    last = idx
    item_lines = []
    (idx + 1).upto(lines.length - 1) do |i|
      break unless lines[i].match?(/\A\s*-\s/)

      item_lines << lines[i]
      last = i
    end

    current = item_lines.map { |l| l.sub(/\A\s*-\s*/, "").strip.gsub(/\A['"]|['"]\z/, "") }
    return lines.join if current == desired

    indent, quote = block_item_shape(item_lines.first)
    rendered = desired.map { |id| "#{indent}- #{quote}#{id}#{quote}\n" }

    # When desired is empty, collapse the block to an inline `key: []` to keep YAML
    # valid (a bare `key:` with no items parses as nil, not an empty array).
    rendered = ["#{key}: []\n"] if desired.empty? && rendered.empty?

    if desired.empty?
      new_lines = lines[0...idx] + rendered + lines[(last + 1)..]
    else
      new_lines = lines[0...idx] + [lines[idx]] + rendered + lines[(last + 1)..]
    end
    new_lines.join
  end

  # Sample indentation and quote char from an existing block item line.
  def block_item_shape(sample)
    return ["", "'"] if sample.nil?

    indent = sample[/\A\s*/].to_s
    value = sample.sub(/\A\s*-\s*/, "").strip
    quote = value.start_with?('"') ? '"' : "'"
    [indent, quote]
  end
end
