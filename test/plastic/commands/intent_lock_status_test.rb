# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/intent_lock_status"

class IntentLockStatusTest < Plastic::TestCase
  def call(*args) = plastic("intent", "lock", "status", *args, table: Plastic::CLI::TABLE)

  def next_line(result) = result.out.lines(chomp: true).find { |line| line.start_with?("next: ") }

  def test_an_intent_with_no_lock_and_no_go_ahead_asks_the_owner_and_offers_no_command
    open_intent

    result = call("1")

    assert_equal [0, "next: none"], [result.code, next_line(result)]
    assert_includes result.out, "because: the owner must give the go-ahead for intent 1"
    assert_includes result.out, "Ask the owner for the go-ahead."
  end

  def test_an_approved_intent_with_no_lock_says_none_and_offers_auto
    write("#{open_intent.dir}/spec.md", "# Spec\n\n## Done criteria\n- It works\n")
    plastic("sync", "up", table: Plastic::CLI::TABLE)
    plastic("intent", "approve", "1", table: Plastic::CLI::TABLE)

    result = call("1")

    assert_equal [0, "next: plastic auto 1 --project global", ""], [result.code, next_line(result), result.err]
    assert_includes result.out, "lock: none\n"
  end

  def test_a_live_lock_offers_the_brief
    open_intent
    store_graphs.work.take_lock("1", session_id: "s-2", mode: "auto")

    result = call("1")

    assert_equal [0, "next: plastic intent brief 1 --project global"], [result.code, next_line(result)]
    assert_includes result.out, "lock: session s-2, mode auto"
  end

  def test_an_unknown_intent_fails
    result = call("9")

    assert_equal [1, nil], [result.code, next_line(result)]
    assert_includes result.err, "no intent 9 in this store"
  end

  def test_no_id_exits_2
    result = call

    assert_equal [2, ""], [result.code, result.out]
    assert_includes result.err, "missing ID"
  end
end
