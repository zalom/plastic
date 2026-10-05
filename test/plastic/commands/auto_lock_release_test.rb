# frozen_string_literal: true

require_relative "auto_lock_test"
require_relative "../../../scripts/lib/plastic/commands/auto_lock_release"

class AutoLockReleaseTest < Plastic::TestCase
  include LockRows

  def release(env: {}) = lock("release", "1", env:)

  def test_the_lock_of_the_calling_session_is_dropped
    open_intent
    hold("s-1")
    result = release(env: { "PLASTIC_SESSION" => "s-1" })

    assert_equal [0, ""], [result.code, result.err]
    assert_empty lock_rows
  end

  def test_a_lapsed_lock_of_another_session_is_dropped
    open_intent
    hold("s-9", renewed_at: "2020-01-01T00:00:00Z")

    assert_equal 0, release(env: { "PLASTIC_SESSION" => "s-1" }).code
    assert_empty lock_rows
  end

  def test_a_live_lock_of_another_session_is_refused_naming_the_holder_and_kept
    open_intent
    hold("s-9")
    result = release(env: { "PLASTIC_SESSION" => "s-1" })

    assert_equal 3, result.code
    assert_match(/s-9/, result.err)
    assert_equal 1, lock_rows.size
  end

  def test_an_intent_with_no_lock_has_nothing_to_release
    open_intent
    result = release(env: { "PLASTIC_SESSION" => "s-1" })

    assert_equal 0, result.code
    assert_match(/no lock/, result.out)
  end
end
