# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"
require_relative "support/codex_binary"
require_relative "../scripts/lib/apply_patch_envelope"

# Intent 239: primary-source the apply_patch V4A grammar against the real codex
# binary. The hermetic tests below read only the checked-in fixture
# (test/fixtures/codex-v4a-grammar.txt); the live tests at the bottom re-extract
# from an installed codex binary and skip cleanly when none resolves.
module CodexV4AGrammarFixture
  module_function

  PATH = File.expand_path("fixtures/codex-v4a-grammar.txt", __dir__)

  def text
    @text ||= File.read(PATH)
  end

  def grammar_section
    header_end = text.index("## Grammar\n") + "## Grammar\n".length
    strictness_start = text.index("\n\n## Strictness strings")
    text[header_end...strictness_start]
  end
end

class CodexV4AGrammarFixtureTest < Minitest::Test
  def fixture
    CodexV4AGrammarFixture.text
  end

  def grammar
    CodexV4AGrammarFixture.grammar_section
  end

  def test_fixture_carries_provenance
    assert_includes fixture, "sha256"
    assert_match %r{/bin/codex\b}, fixture
    assert_includes fixture, "271056976 bytes"
    assert_includes fixture, "Do not hand-edit: regenerate from the binary."
  end

  def test_fixture_carries_every_production
    %w[start: begin_patch: end_patch: hunk: add_hunk: delete_hunk: update_hunk:
       filename: add_line: change_move: change: change_context: change_line:
       eof_line: environment_id:].each do |production|
      assert_includes grammar, production, "missing production #{production}"
    end
  end

  # Pulls the literal prefix out of a regex like /\A\*\*\* Add File: (.+)\z/, so this
  # test compares the parser's REAL constants against the real grammar rather than a
  # copy of the same string typed twice (a mutated ADD_RE etc must turn this RED).
  def literal_prefix(regexp)
    m = regexp.source.match(/\A\\A(.+?)\(/) or raise "cannot extract literal prefix from #{regexp.inspect}"
    m[1].gsub(/\\(.)/, '\1')
  end

  def test_parser_markers_are_real_grammar_terminals
    assert_includes grammar, "\"#{ApplyPatchEnvelope::BEGIN_MARK}\""
    assert_includes grammar, "\"#{ApplyPatchEnvelope::END_MARK}\""
    assert_includes grammar, "\"#{literal_prefix(ApplyPatchEnvelope::ADD_RE)}\""
    assert_includes grammar, "\"#{literal_prefix(ApplyPatchEnvelope::UPDATE_RE)}\""
    assert_includes grammar, "\"#{literal_prefix(ApplyPatchEnvelope::DELETE_RE)}\""
    assert_includes grammar, "\"#{literal_prefix(ApplyPatchEnvelope::MOVE_RE)}\""
  end

  def test_parser_is_laxer_than_codex_on_envelope_position
    envelope = <<~TEXT
      Here is a patch for you to apply.
      *** Begin Patch
      *** Add File: a.md
      +hello
      *** End Patch
      Thanks!
    TEXT
    ops = ApplyPatchEnvelope.parse(envelope)
    assert_equal 1, ops.size, "our parser scans for markers anywhere and should accept prose around the envelope"

    assert_includes fixture, "The first line of the patch must be",
      "codex itself requires the envelope to START with *** Begin Patch, so a laxer gate is the safe direction"
  end

  def test_environment_id_line_is_tolerated
    without_env = <<~TEXT
      *** Begin Patch
      *** Add File: a.md
      +line one
      *** End Patch
    TEXT
    with_env = <<~TEXT
      *** Begin Patch
      *** Environment ID: env_abc123
      *** Add File: a.md
      +line one
      *** End Patch
    TEXT
    ops_without = ApplyPatchEnvelope.parse(without_env)
    ops_with = ApplyPatchEnvelope.parse(with_env)
    assert_equal ops_without.map { |o| [o.op, o.path, o.added_content] },
                 ops_with.map { |o| [o.op, o.path, o.added_content] }
  end

  def test_end_of_file_marker_is_tolerated
    without_eof = <<~TEXT
      *** Begin Patch
      *** Update File: a.md
      @@
      +line one
      *** End Patch
    TEXT
    with_eof = <<~TEXT
      *** Begin Patch
      *** Update File: a.md
      @@
      +line one
      *** End of File
      *** End Patch
    TEXT
    ops_without = ApplyPatchEnvelope.parse(without_eof)
    ops_with = ApplyPatchEnvelope.parse(with_eof)
    assert_equal ops_without.map { |o| [o.op, o.path, o.added_content] },
                 ops_with.map { |o| [o.op, o.path, o.added_content] }
    refute_includes ops_with.first.added_content, "End of File"
  end

  def test_freeform_argv_form_parses
    ops = ApplyPatchEnvelope.parse(["apply_patch", "*** Begin Patch\n*** Add File: a.md\n+x\n*** End Patch\n"])
    assert_equal 1, ops.size
    assert_equal :add, ops.first.op
    assert_equal "a.md", ops.first.path
  end
end

class CodexV4AGrammarLiveTest < Minitest::Test
  def setup
    @bin = CodexBinary.resolve
    skip "no native codex binary found on this machine; fixture-only run" if @bin.nil?
  end

  def test_the_fixture_still_matches_the_real_binary
    assert_equal CodexV4AGrammarFixture.grammar_section, CodexBinary.grammar(@bin),
      "the checked-in grammar fixture has drifted from the installed codex binary"
  end

  def test_the_real_binary_carries_every_strictness_string
    CodexBinary::STRICTNESS_STRINGS.each do |s|
      assert CodexBinary.carries?(@bin, s), "codex binary should carry #{s.inspect}"
    end
  end
end
