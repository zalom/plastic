# frozen_string_literal: true

require_relative "../../../test_helper"

class IntentOpenTest < Plastic::TestCase
  def status = retrieval.intent("1").status

  def index_status = JSON.parse(File.read(store_path("store/index.json"))).fetch("intents").find { |entry| entry.fetch("intent_id") == "1" }.fetch("status")

  def test_a_future_intent_opens_and_offers_the_next_command
    open_intent(status: "future")

    assert_case line("intent open 1"), code: 0, out: ["opened: 1", "next: plastic next"]
    assert_equal "open", status
  end

  def test_a_parked_intent_opens_without_its_reason
    open_intent(status: "parked", reason: "waits for the beta")

    assert_case line("intent open 1"), code: 0, out: ["opened: 1"]
    assert_equal ["open", nil], retrieval.intent("1").to_h.values_at(:status, :reason)
  end

  def test_the_opened_intent_prints_into_the_store_index
    open_intent(status: "future")
    line("intent open 1")

    assert_equal "open", index_status
  end

  %w[open in_progress done abandoned].each do |found|
    define_method(:"test_an_#{found}_intent_is_refused_with_exit_3_and_keeps_its_status") do
      open_intent(status: found)

      assert_case line("intent open 1"), code: 3, out: "", err: ["intent 1 is #{found}; only a future or parked intent opens"]
      assert_equal found, status
    end
  end

  def test_a_missing_intent_exits_1_and_names_it
    assert_case line("intent open 9"), code: 1, out: "", err: ["no intent 9 in this store"]
  end
end
