# frozen_string_literal: true

require_relative "../../test_helper"

class IntentAbandonTest < Plastic::TestCase
  include LifecycleHelper

  REVERTED = "\n## Verification\n- Reverted: nothing delivered\n"

  def droppable(reverted: true, **fields)
    intent = open_intent("Alpha", **fields)
    write("#{intent.dir}/outcome.md", "# Outcome\n\nDropped: the need went away.\n#{REVERTED if reverted}")
    cli("sync", "up")
    intent
  end

  def abandon(*extra) = cli("intent", "abandon", "1", *extra)

  def supersede(from, to)
    store_graphs.databases.fetch(:knowledge).transaction do |batch|
      batch.put(:links, { from_ref: from, to_ref: to, kind: "supersedes", at: LifecycleHelper::EARLY })
    end
  end

  def test_an_option_is_a_usage_error
    droppable

    assert_equal [2, "open"], [abandon("--judge", "agent").code, retrieval.intent("1").status]
  end

  def test_without_the_reverted_bullet_it_hands_over_the_revert_steps
    droppable(reverted: false)
    result = abandon

    assert_equal [0, "open"], [result.code, retrieval.intent("1").status]
    assert_includes result.out, "Reverted:"
  end

  def test_with_the_reverted_bullet_it_closes_cancelled_with_no_completion
    droppable
    result = abandon

    assert_equal 0, result.code
    assert_equal ["abandoned", "cancelled", nil], [retrieval.intent("1").status, retrieval.intent("1").disposition, retrieval.completion("1")]
  end

  def test_it_releases_the_lock
    droppable
    cli("auto", "1")
    abandon

    assert_nil retrieval.lock("1")
  end

  def test_a_supersedes_link_from_another_intent_gives_superseded
    droppable
    open_intent("Beta")
    supersede("2", "1")
    abandon

    assert_equal "superseded", retrieval.intent("1").disposition
  end

  def test_a_supersedes_link_from_this_intent_to_another_gives_cancelled
    droppable
    open_intent("Beta")
    supersede("1", "2")
    abandon

    assert_equal "cancelled", retrieval.intent("1").disposition
  end

  def test_a_supersedes_link_between_rulings_of_this_intent_gives_cancelled
    droppable
    supersede("1/D2", "1")
    abandon

    assert_equal "cancelled", retrieval.intent("1").disposition
  end

  %w[done abandoned].each do |status|
    define_method(:"test_a_#{status}_intent_fails") do
      open_intent(status:)

      assert_equal 1, abandon.code
    end
  end

  def test_a_live_foreign_lock_refuses_with_exit_3
    droppable
    store_graphs.work.take_lock("1", session_id: "someone-else", mode: "auto")

    assert_equal [3, "open"], [abandon.code, retrieval.intent("1").status]
  end
end
