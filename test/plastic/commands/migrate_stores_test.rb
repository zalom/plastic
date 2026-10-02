# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/migrate_stores"
require_relative "../../../scripts/lib/plastic/commands/roadmap_show"

class MigrateStoresTest < Plastic::TestCase
  fixtures :legacy

  ROADMAP = <<~MARKDOWN
    # Ship the client

    ## Batches

    - [x] 1 Build ai-infra — delivered
    - [ ] 1a Deploy the gateway — queued
  MARKDOWN

  def apply = plastic("migrate", "stores", "--apply", table: Plastic::CLI::TABLE)

  def spec_with(decisions) = "# Spec\n\n## Decisions\n#{decisions.map { |line| "- #{line}\n" }.join}"

  def test_colliding_ruling_ids_take_the_next_free_number
    write("store/1--ai-infra/spec.md", spec_with(["D1 Use Proxmox", "D1 Use LiteLLM", "Keep it local"]))

    apply

    assert_equal %w[D1 D2 D3], retrieval.rulings("1").map(&:id)
  end

  def test_spec_decisions_win_over_the_intent_file
    write("store/1--ai-infra/spec.md", spec_with(["D1 Use Proxmox"]))
    write("store/1--ai-infra/1--ai-infra.md", "#{folder.read("store/1--ai-infra/1--ai-infra.md")}\n## Decisions\n- D1 Use Proxmox servers\n")

    apply

    assert_equal ["D1 Use Proxmox"], retrieval.rulings("1").map(&:text)
  end

  def test_a_roadmap_with_no_batch_heading_lands_in_batch_one
    write("roadmaps/ship.md", ROADMAP)

    apply

    assert_equal [[1, "Ship the client"]], retrieval.batches("ship").map { |batch| [batch.position, batch.title] }
    assert_equal [1, 1], retrieval.roadmap_items("ship").map(&:batch)
  end

  def test_an_imported_item_names_the_intent_with_its_id
    write("roadmaps/ship.md", ROADMAP)

    apply

    assert_equal %w[1 1a], retrieval.roadmap_items("ship").map(&:intent_id)
  end

  def test_savepoint_lines_join_the_roadmap_log
    write("roadmaps/ship.md", ROADMAP)
    write("roadmaps/ship.savepoint.md", "2026-09-01T10:00:00+02:00 Batch 1 opened\n")

    apply

    assert_equal ["Batch 1 opened"], retrieval.roadmap_log("ship").map(&:text)
    assert_nil retrieval.roadmap("ship.savepoint")
  end

  def test_a_second_apply_says_no_store_is_left
    apply

    assert_includes apply.out, "total: no store left to import"
  end

  def test_a_batch_with_no_goal_prints_without_a_dash
    write("roadmaps/ship.md", ROADMAP)
    apply

    result = plastic("roadmap", "show", "ship", table: Plastic::CLI::TABLE)

    assert_includes result.out, "batch 1: Ship the client\n"
  end
end
