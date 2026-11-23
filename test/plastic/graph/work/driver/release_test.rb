# frozen_string_literal: true

require_relative "../../../../test_helper"

# Closing an intent releases its driver claim, whoever holds it, and leaves the claims of other intents.
class WorkDriverReleaseTest < Plastic::TestCase
  def setup
    super
    %w[Alpha Beta].each_with_index do |title, index|
      store_graphs.work.write_intent(title:)
      store_graphs.work.activate_intent((index + 1).to_s)
    end
  end

  def work = Plastic::Graph.open(home: @plastic_home, store: "global", session: "s-1").work

  def claimed = store_graphs.databases.fetch(:store).rows("SELECT intent_id FROM drivers").map { |row| row["intent_id"] }

  def test_releasing_an_intent_deletes_its_claim_and_names_the_holder
    work.drive_intent(intent_id: "1", by: "s-1")

    assert_equal ["s-1", []], [work.release_driver("1"), claimed]
  end

  def test_releasing_an_intent_leaves_the_claim_of_another_intent
    %w[1 2].each { |id| work.drive_intent(intent_id: id, by: "s-1") }
    work.release_driver("1")

    assert_equal ["2"], claimed
  end

  def test_releasing_an_intent_nobody_drives_names_no_holder
    assert_nil work.release_driver("1")
  end
end
