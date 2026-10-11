# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/harnesses/session_rows"

class HarnessSessionRowsTest < Plastic::TestCase
  def rows = Plastic::Harnesses::SessionRows.new(@plastic_home)

  def seed(session_id, harness:, started_at:)
    Plastic::Graph::Database::Local.new(@plastic_home).transaction do |batch|
      batch.put(:sessions, { session_id:, harness:, started_at: })
    end
  end

  def test_the_harness_of_a_session_comes_from_its_row
    seed("s-1", harness: "codex", started_at: "2026-10-11T10:00:00Z")

    assert_equal "codex", rows.harness("s-1")
  end

  def test_a_session_with_no_row_has_no_harness
    assert_nil rows.harness("s-9")
  end

  def test_the_latest_started_session_is_picked
    seed("c-1", harness: "claude-code", started_at: "2026-10-11T10:00:00Z")
    seed("x-1", harness: "codex", started_at: "2026-10-11T11:00:00Z")

    assert_equal "x-1", rows.latest(%w[c-1 x-1])
  end

  def test_with_no_rows_none_is_picked_and_no_database_is_made
    bare = Dir.mktmpdir

    assert_nil Plastic::Harnesses::SessionRows.new(bare).latest(%w[c-1 x-1])
    refute_path_exists File.join(bare, "local.db")
  end
end
