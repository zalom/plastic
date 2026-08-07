# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/spec_header"

# SpecHeader (intent 213): the single parser for the Tier: and Settled: lines that live
# above the `# Spec:` heading in a spec.md header block. Hermetic Minitest, no eval, no
# ambient session id, no network. Every disk fixture lives under Dir.mktmpdir.
class SpecHeaderTest < Minitest::Test
  def test_parses_tier_and_settled_with_reason
    result = SpecHeader.parse("Tier: L\nSettled: yes (owner ruled it settled)\n\n# Spec: x\n")
    assert_equal({ tier: "L", settled: true, settled_reason: "owner ruled it settled" }, result)
  end

  # BLOCKING 5: the parenthesised reason is REQUIRED. D2 calls Settled a ONE-WAY DOOR, so
  # leniency accepted now (a bare "Settled: yes" counting as settled) could never be
  # tightened later without a breaking change; this stays strict from the start.
  def test_settled_yes_without_parens_is_not_settled
    result = SpecHeader.parse("Tier: M\nSettled: yes\n\n# Spec: x\n")
    assert_equal false, result[:settled]
    assert_nil result[:settled_reason]
  end

  def test_absent_settled_line_means_not_settled
    result = SpecHeader.parse("Tier: M\n\n# Spec: x\n")
    assert_equal false, result[:settled]
    assert_nil result[:settled_reason]
  end

  def test_settled_no_is_not_a_defined_variant_and_is_not_settled
    result = SpecHeader.parse("Tier: M\nSettled: no\n\n# Spec: x\n")
    assert_equal false, result[:settled]
  end

  def test_settled_line_below_the_spec_heading_is_not_parsed
    result = SpecHeader.parse("Tier: M\n\n# Spec: x\nSettled: yes (too late)\n")
    assert_equal false, result[:settled]
    assert_nil result[:settled_reason]
  end

  def test_each_valid_tier_value_parses
    assert_equal "S", SpecHeader.parse("Tier: S\n\n# Spec: x\n")[:tier]
    assert_equal "M", SpecHeader.parse("Tier: M\n\n# Spec: x\n")[:tier]
    assert_equal "L", SpecHeader.parse("Tier: L\n\n# Spec: x\n")[:tier]
  end

  def test_invalid_tier_values_yield_nil
    assert_nil SpecHeader.parse("Tier: XL\n\n# Spec: x\n")[:tier]
    assert_nil SpecHeader.parse("Tier: s\n\n# Spec: x\n")[:tier]
    assert_nil SpecHeader.parse("Tier:\n\n# Spec: x\n")[:tier]
  end

  def test_placeholder_sentinel_first_line_is_skipped_not_a_terminator
    result = SpecHeader.parse("<!-- plastic:placeholder -->\nTier: S\n\n# Spec: x\n")
    assert_equal "S", result[:tier]
  end

  def test_parse_file_on_missing_path_returns_all_nil_and_does_not_raise
    Dir.mktmpdir("spec-header") do |dir|
      missing = File.join(dir, "spec.md")
      result = SpecHeader.parse_file(missing)
      assert_equal({ tier: nil, settled: false, settled_reason: nil }, result)
    end
  end

  def test_render_with_tier_and_reason
    assert_equal "Tier: L\nSettled: yes (r)\n", SpecHeader.render(tier: "L", settled_reason: "r")
  end

  def test_render_with_no_tier_and_no_reason_uses_placeholder_and_omits_settled
    assert_equal "Tier: S|M|L\n", SpecHeader.render(tier: nil, settled_reason: nil)
  end

  # BLOCKING 4: the original guard substring-matched exactly one regex spelling
  # ('Tier:\s*(S|M|L)'), so a second parser written with different whitespace/anchors
  # (or one parsing Settled: instead) passed clean, and Settled: was never checked at
  # all. This version scans scripts/, hooks/, skills/, agents/, and templates/, and
  # flags a line only when it embeds an actual regex/parsing construct (a /.../ or
  # %r{...} regex literal, or a call to .match(/.match?(/=~/Regexp.new(/.scan(/
  # grep -E/egrep/sed -E) whose OWN text mentions "Tier:" or "Settled:". Prose that
  # merely names the line (a comment, a doc example, an agent brief) has no such
  # construct on the line, so it is left alone; a file with unrelated regex machinery
  # elsewhere (bridge.rb has plenty, for checklists and INDEX lines) is also left
  # alone, because THOSE lines never mention "Tier:" or "Settled:" themselves.
  def test_only_spec_header_implements_the_tier_grammar
    root = File.expand_path("..", __dir__)
    offenders = []

    %w[scripts hooks skills agents templates].each do |top|
      Dir[File.join(root, top, "**", "*")].each do |path|
        next unless File.file?(path)
        next if path.end_with?("scripts/lib/spec_header.rb")

        content = begin
          File.read(path)
        rescue StandardError
          nil
        end
        next unless content

        offending_line = content.each_line.find { |line| second_parser_line?(line) }
        offenders << path.sub("#{root}/", "") if offending_line
      end
    end

    assert_empty offenders,
                 "a second Tier:/Settled: parser was introduced outside " \
                 "scripts/lib/spec_header.rb; delegate to SpecHeader instead: " \
                 "#{offenders.join(', ')}"
  end

  GRAMMAR_TOKENS = ["Tier:", "Settled:"].freeze
  PARSING_CALL_RE = /\.match\?\(|\.match\(|=~|Regexp\.new\(|\.scan\(|grep\s+-E|egrep|sed\s+-E/

  def second_parser_line?(line)
    return false unless GRAMMAR_TOKENS.any? { |t| line.include?(t) }

    regex_literal_bodies(line).any? { |body| GRAMMAR_TOKENS.any? { |t| body.include?(t) } } ||
      line.match?(PARSING_CALL_RE)
  end

  def regex_literal_bodies(line)
    bodies = []
    line.scan(%r{/([^/\n]*)/}) { |m| bodies << m[0] }
    line.scan(/%r\{([^}\n]*)\}/) { |m| bodies << m[0] }
    bodies
  end
end
