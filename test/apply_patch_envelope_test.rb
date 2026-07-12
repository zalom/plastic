require "minitest/autorun"
require_relative "../scripts/lib/apply_patch_envelope"

# Pure-function coverage for the Codex apply_patch V4A envelope parser (intent
# 102, Step 2). No IO except a stderr warn on failure, so no tmpdir/hermeticity
# scaffolding is needed here.
class ApplyPatchEnvelopeTest < Minitest::Test
  def test_single_add_returns_full_content
    command = <<~PATCH
      *** Begin Patch
      *** Add File: store/1--x/spec.md
      +line one
      +line two
      *** End Patch
    PATCH

    ops = ApplyPatchEnvelope.parse(command)

    assert_equal 1, ops.size
    assert_equal :add, ops[0].op
    assert_equal "store/1--x/spec.md", ops[0].path
    assert_equal "line one\nline two\n", ops[0].added_content
  end

  def test_single_update_returns_only_added_lines
    command = <<~PATCH
      *** Begin Patch
      *** Update File: store/1--x/plan.md
      @@
       unchanged context line
      -removed line
      +added line
      *** End Patch
    PATCH

    ops = ApplyPatchEnvelope.parse(command)

    assert_equal 1, ops.size
    assert_equal :update, ops[0].op
    assert_equal "store/1--x/plan.md", ops[0].path
    assert_equal "added line\n", ops[0].added_content
  end

  def test_bundle_returns_ops_in_order
    command = <<~PATCH
      *** Begin Patch
      *** Add File: a.md
      +new a
      *** Update File: b.md
      @@
      +updated b
      *** Delete File: c.md
      *** End Patch
    PATCH

    ops = ApplyPatchEnvelope.parse(command)

    assert_equal [:add, :update, :delete], ops.map(&:op)
    assert_equal %w[a.md b.md c.md], ops.map(&:path)
    assert_equal "new a\n", ops[0].added_content
    assert_equal "updated b\n", ops[1].added_content
    assert_nil ops[2].added_content
  end

  def test_update_followed_by_move_to_sets_new_path
    command = <<~PATCH
      *** Begin Patch
      *** Update File: old/path.md
      @@
      +renamed content
      *** Move to: new/path.md
      *** End Patch
    PATCH

    ops = ApplyPatchEnvelope.parse(command)

    assert_equal 1, ops.size
    assert_equal "new/path.md", ops[0].path
    assert_equal "renamed content\n", ops[0].added_content
  end

  def test_empty_string_returns_empty_array
    assert_equal [], ApplyPatchEnvelope.parse("")
  end

  def test_non_patch_text_returns_empty_array
    assert_equal [], ApplyPatchEnvelope.parse("just some ordinary shell command\n")
  end

  def test_truncated_envelope_begin_without_end_returns_empty_array
    command = "*** Begin Patch\n*** Add File: a.md\n+content\n"

    assert_equal [], ApplyPatchEnvelope.parse(command)
  end

  def test_nil_command_returns_empty_array
    assert_equal [], ApplyPatchEnvelope.parse(nil)
  end

  # Adversarial: a body line that itself reads like a section marker (prefixed
  # with '+', i.e. it is CONTENT of the file being added, not a real marker)
  # must not be mistaken for a second op. The marker regexes are anchored with
  # \A\*\*\*, so a '+*** Add File: fake' line never matches ADD_RE etc.
  def test_adversarial_embedded_marker_does_not_create_second_op
    command = <<~PATCH
      *** Begin Patch
      *** Add File: real.md
      +normal line
      +*** Add File: fake.md
      +more content
      *** End Patch
    PATCH

    ops = ApplyPatchEnvelope.parse(command)

    assert_equal 1, ops.size
    assert_equal "real.md", ops[0].path
    assert_equal "normal line\n*** Add File: fake.md\nmore content\n", ops[0].added_content
  end

  def test_array_command_is_joined_and_parsed
    command = ["*** Begin Patch", "*** Add File: a.md", "+content", "*** End Patch"]

    ops = ApplyPatchEnvelope.parse(command)

    assert_equal 1, ops.size
    assert_equal :add, ops[0].op
    assert_equal "content\n", ops[0].added_content
  end
end
