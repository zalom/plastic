# encoding: UTF-8
# frozen_string_literal: true

require "yaml"

# SkillLint: deterministic, dependency-injected engine that runs five
# structural checks over a directory of Agent Skills (intent 85b).
#
# Pure and DI: constructed with an injected `skills_dir`, performs no writes,
# no `eval`, and reads no ambient config beyond the injected directory. Mirrors
# the CLI-over-lib shape of `scripts/lib/intent_validator.rb`: the `skill-lint`
# CLI (ACTION_2) is a thin wrapper, `scripts/doctor.rb` (ACTION_4) consumes the
# same engine for an advisory finding, and `test/skill_lint_test.rb` (ACTION_3)
# proves every check red-and-green plus a no-skip-list live-tree guard.
#
# Each violation is a Hash:
#   { check:, skill:, file:, line:, rule:, message: }
# `check` is one of the five check-ids below, `skill` is the skill directory
# basename, `file` is the offending path, `line` is an Integer where locatable
# else nil, `rule` cites the standard being enforced, `message` is an
# actionable fix instruction.
class SkillLint
  # A binding keyword: a mention's paragraph carries an observable trigger
  # condition when it names one of these (word-boundary, case-insensitive).
  BINDING_KEYWORD_RE = /\b(when|if|before|after|while)\b/i

  # A `to <verb>` or `for <noun-phrase>` purpose clause.
  PURPOSE_RE = /\b(to|for)\s+\S/i

  Result = Struct.new(:violations) do
    def ok?
      violations.empty?
    end

    # Slice violations down to one check-id, e.g. for a doctor finding or a
    # red-proof assertion.
    def violations_for(check_id)
      violations.select { |v| v[:check] == check_id }
    end
  end

  def initialize(skills_dir:)
    @skills_dir = skills_dir
  end

  def run
    violations = []

    skill_md_paths.each do |skill_md|
      skill_dir = File.dirname(skill_md)
      content = File.read(skill_md)

      violations.concat(check_body_budget(skill_dir, skill_md, content))
      violations.concat(check_frontmatter_validity(skill_dir, skill_md, content))
      violations.concat(check_bare_pointer(skill_dir, skill_md, content))
      violations.concat(check_orphan_files(skill_dir))
      violations.concat(check_references_depth(skill_dir))
    end

    Result.new(violations)
  end

  private

  def skill_md_paths
    Dir.glob(File.join(@skills_dir, "*", "SKILL.md")).sort
  end

  def skill_name(skill_dir)
    File.basename(skill_dir)
  end

  def violation(check:, skill:, file:, line:, rule:, message:)
    { check: check, skill: skill, file: file, line: line, rule: rule, message: message }
  end

  # Frontmatter split uses the shared convention (scripts/lib/intent_validator.rb):
  # `content.split("---", 3)`; parts[1] is the frontmatter text, parts[2] is the
  # body. Also computes the body's starting line number (0-based line count of
  # everything before the body) so callers can report absolute file line
  # numbers, not just body-relative ones.
  def frontmatter_and_body(content)
    parts = content.split("---", 3)
    return { frontmatter: nil, body: content, body_offset_lines: 0 } if parts.length < 3

    prefix_len = parts[0].length + 3 + parts[1].length + 3
    prefix = content[0...prefix_len]
    { frontmatter: parts[1], body: parts[2], body_offset_lines: prefix.count("\n") }
  end

  # --- 1. body-budget ---

  def check_body_budget(skill_dir, skill_md, content)
    violations = []
    body = frontmatter_and_body(content)[:body]
    name = skill_name(skill_dir)

    line_count = body.lines.count
    if line_count >= 500
      violations << violation(
        check: "body-budget", skill: name, file: skill_md, line: nil,
        rule: "body under 500 lines",
        message: "SKILL.md body is #{line_count} lines; move detail into references/*.md to get under 500"
      )
    end

    tokens = (body.split(/\s+/).reject(&:empty?).length * 1.3).round
    if tokens >= 5000
      violations << violation(
        check: "body-budget", skill: name, file: skill_md, line: nil,
        rule: "body under about 5000 tokens (word-based estimate)",
        message: "SKILL.md body is about #{tokens} tokens (word-based estimate); move detail into references/*.md to get under 5000"
      )
    end

    violations
  end

  # --- 2. frontmatter-validity ---

  def check_frontmatter_validity(skill_dir, skill_md, content)
    violations = []
    name = skill_name(skill_dir)
    frontmatter_text = frontmatter_and_body(content)[:frontmatter]

    begin
      fm = YAML.safe_load(frontmatter_text.to_s)
    rescue Psych::SyntaxError
      violations << violation(
        check: "frontmatter-validity", skill: name, file: skill_md, line: nil,
        rule: "frontmatter must survive strict YAML.safe_load",
        message: "SKILL.md frontmatter fails YAML.safe_load; quote scalar values that contain an unquoted \": \" sequence"
      )
      return violations
    end
    fm = {} unless fm.is_a?(Hash)

    expected_name = "plastic-#{name}"
    if fm["name"] != expected_name
      violations << violation(
        check: "frontmatter-validity", skill: name, file: skill_md, line: nil,
        rule: "name: must equal plastic-<directory>",
        message: "frontmatter name: is #{fm["name"].inspect}; expected #{expected_name.inspect}"
      )
    end

    user_invocable = fm["user-invocable"]
    unless user_invocable == true || user_invocable == false
      violations << violation(
        check: "frontmatter-validity", skill: name, file: skill_md, line: nil,
        rule: "user-invocable: must be present and boolean",
        message: "frontmatter user-invocable: is #{user_invocable.inspect}; must be present and true or false"
      )
    end

    violations
  end

  # --- 3. bare-pointer ---

  def check_bare_pointer(skill_dir, skill_md, content)
    violations = []
    ref_files = Dir.glob(File.join(skill_dir, "references", "*.md")).sort
    return violations if ref_files.empty?

    parsed = frontmatter_and_body(content)
    body_lines = parsed[:body].lines
    offset = parsed[:body_offset_lines]
    blocks = paragraph_blocks(body_lines)
    name = skill_name(skill_dir)

    ref_files.each do |ref_file|
      base = File.basename(ref_file)
      mention_indices = (0...body_lines.length).select { |i| body_lines[i].include?(base) }
      next if mention_indices.empty? # zero mentions is an orphan (check 4), not a bare pointer

      bound = mention_indices.any? { |i| bound_mention?(body_lines[i], i, blocks, base) }
      next if bound

      first = mention_indices.first
      violations << violation(
        check: "bare-pointer", skill: name, file: skill_md, line: offset + first + 1,
        rule: "every reference link must bind to an observable trigger condition, never a bare pointer",
        message: "#{base} is only ever a bare pointer; add a when/if/before/after/while clause or a " \
                  "to/for purpose so the trigger is observable"
      )
    end

    violations
  end

  def bound_mention?(line, index, blocks, base)
    stripped = line.strip
    return table_row_bound?(stripped, base) if stripped.start_with?("|")

    block = blocks.find { |b| index.between?(b[:start], b[:end]) }
    block_text = block ? block[:text] : line

    # Narrow to the unit(s) that actually mention the reference, so an
    # unrelated unit elsewhere in the same paragraph cannot launder a
    # genuinely bare pointer through an incidental "to"/"for" (an ordinary
    # preposition, not a binding purpose clause). Split on BOTH sentence
    # boundaries (.!?) AND list-item starts, so a bullet list (which has no
    # terminal punctuation between items) does not collapse into one unit
    # whose bound siblings launder a bare bullet -- the trailing "References"
    # list pattern (most bullets bound, one forgotten) this linter exists to
    # catch. Keep only units that mention `base`. Falls back to the whole
    # block when no unit boundary contains the mention (e.g. a mid-sentence
    # line wrap with no terminal punctuation nearby), so the legitimate
    # multi-line-wrapped case still binds.
    #
    # Known conservative limitation (documented, not closed): a bare mention
    # with NO unit boundary of its own (no leading list marker, no preceding
    # terminal punctuation) immediately followed by an unrelated sentence
    # carrying "to"/"for" can still borrow that neighbor's binding via the
    # empty-fallback path. Closing this structurally risks re-breaking the
    # legitimate wrapped-sentence case (which also relies on the fallback),
    # so it stays open; see intent 85b insights.
    units = block_text.split(/(?<=[.!?])\s+|\n(?=\s*(?:[-*+]|\d+[.)])\s)/)
    mentioning = units.select { |s| s.include?(base) }
    scoped_text = mentioning.empty? ? block_text : mentioning.join(" ")

    scoped_text.match?(BINDING_KEYWORD_RE) || scoped_text.match?(PURPOSE_RE)
  end

  # A table row is bound when some OTHER cell (not the one carrying the
  # reference path) has visible text (the trigger-condition column).
  def table_row_bound?(stripped_line, base)
    cells = stripped_line.split("|").map(&:strip).reject(&:empty?)
    other_cells = cells.reject { |c| c.include?(base) }
    !other_cells.empty?
  end

  # Group body lines into blank-line-delimited paragraph blocks so a mention
  # that trails a wrapped sentence (the binding keyword on the line above) is
  # still evaluated against its full paragraph, not just its own physical line.
  def paragraph_blocks(lines)
    blocks = []
    start = nil
    lines.each_with_index do |line, i|
      if line.strip.empty?
        blocks << { start: start, end: i - 1, text: lines[start..(i - 1)].join } if start
        start = nil
      else
        start ||= i
      end
    end
    blocks << { start: start, end: lines.length - 1, text: lines[start..-1].join } if start
    blocks
  end

  # --- 4. orphan-files ---

  def check_orphan_files(skill_dir)
    violations = []
    ref_files = Dir.glob(File.join(skill_dir, "references", "*.md")).sort
    return violations if ref_files.empty?

    other_files = Dir.glob(File.join(skill_dir, "**", "*")).select { |p| File.file?(p) }
    name = skill_name(skill_dir)

    ref_files.each do |ref_file|
      base = File.basename(ref_file)
      mentioned = other_files.any? do |other|
        next false if other == ref_file

        File.read(other).include?(base)
      end
      next if mentioned

      violations << violation(
        check: "orphan-files", skill: name, file: ref_file, line: nil,
        rule: "every references/ file must be routed from the skill",
        message: "#{base} is never mentioned anywhere in the skill directory; route it from SKILL.md or delete it"
      )
    end

    violations
  end

  # --- 5. references-depth ---

  def check_references_depth(skill_dir)
    violations = []
    refs_root = File.join(skill_dir, "references")
    return violations unless File.directory?(refs_root)

    name = skill_name(skill_dir)
    Dir.glob(File.join(refs_root, "**", "*")).each do |path|
      next unless File.file?(path)

      rel = path.sub("#{refs_root}/", "")
      next unless rel.include?("/")

      violations << violation(
        check: "references-depth", skill: name, file: path, line: nil,
        rule: "references stay one level deep",
        message: "#{rel} is nested under references/; move it to a flat references/*.md file"
      )
    end

    violations
  end
end
