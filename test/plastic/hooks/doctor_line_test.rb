# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/hooks/doctor_line"

class DoctorLineTest < Minitest::Test
  TWO = ->(_scope, _harness) { %w[launcher hooks] }
  NONE = ->(_scope, _harness) { [] }

  def line(harness, source: "startup", session_id: "s-1", health: TWO, err: StringIO.new)
    Plastic::Hooks::DoctorLine.new(:scope, harness, session_id:, health:, err:).line(source)
  end

  def test_a_registered_harness_with_failing_checks_counts_them
    assert_equal "Plastic: doctor found 2 failing checks; run plastic doctor.", line("codex")
  end

  def test_a_registered_harness_with_every_check_passing_gives_no_line
    assert_nil line("codex", health: NONE)
  end

  def test_a_resumed_session_gives_no_line
    assert_nil line("unknown", source: "resume")
  end

  def test_an_unregistered_name_with_no_session_gives_no_line
    assert_nil line("unknown", session_id: nil)
  end

  def test_an_unknown_session_names_only_the_harnesses_the_doctor_has_checks_for
    assert_equal "Plastic: the session s-1 is recorded as unknown: its start hook found no sign of a registered harness; " \
                 "run plastic doctor --harness with one of claude-code, codex.", line("unknown")
  end

  def test_the_doctor_is_asked_with_the_scope_and_the_harness
    asked = []
    line("claude-code", health: ->(scope, harness) { asked << [scope, harness] && [] })

    assert_equal [[:scope, "claude-code"]], asked
  end

  def test_a_doctor_that_breaks_says_so_on_the_error_stream_and_gives_no_line
    err = StringIO.new

    assert_nil line("codex", health: ->(_scope, _harness) { raise "the doctor broke" }, err:)
    assert_equal "plastic hook: the doctor broke\n", err.string
  end
end
