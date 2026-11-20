# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/knowledge/resources/sort"
require_relative "../../../../test_helpers/resources_homes"

# A sort that rewrites a link in a core file of a closed intent says so on that intent's work log, in its output and in its preview.
class ResourcesAmendmentSortTest < Plastic::TestCase
  include ResourcesHomes

  fixtures :alpha_synced

  Resources = Plastic::Graph::Knowledge::Resources
  REASON = "the resource sort moved its target"
  AMENDED = [
    ["spec.md", "spec.md: link reviews/r1.md -> resources/tmp/reviews/r1.md; #{REASON}"],
    ["spec.md", "spec.md: link resources/notes.md -> resources/tmp/notes.md; #{REASON}"]
  ].freeze

  def folder = Plastic::Graph::Knowledge::StoreFolder.new(store_root)

  def sort = Resources::Sort.new(folder, store_graphs).call

  def close(status) = store_database.transaction { |batch| batch.write(:intents, "UPDATE intents SET status = :status WHERE intent_id = '1'", status:) }

  def amended = store_database.rows("SELECT path, text FROM work_log WHERE kind = 'amended' ORDER BY position").map(&:values)

  def setup
    super
    write_old_layout
  end

  def test_a_rewrite_in_a_core_file_of_a_done_intent_writes_one_amended_line_for_each_link
    close("done")
    sort

    assert_equal AMENDED, amended
  end

  def test_an_abandoned_intent_is_amended_too
    close("abandoned")
    sort

    assert_equal AMENDED, amended
  end

  def test_the_amended_line_holds_the_sha_of_the_new_text
    close("done")
    sort
    sha = store_database.rows("SELECT sha256 FROM work_log WHERE kind = 'amended'").map { |row| row.fetch("sha256") }.uniq

    assert_equal [Digest::SHA256.hexdigest(File.read(File.join(store_root, INTENT, "spec.md")))], sha
  end

  def test_the_output_of_the_sort_lists_each_amendment
    close("done")

    assert_includes sort, "amended #{INTENT}/spec.md: link reviews/r1.md -> resources/tmp/reviews/r1.md; #{REASON}"
  end

  def test_an_open_intent_gets_no_amended_line
    sort

    assert_equal [], amended
  end

  def test_the_plan_names_each_amendment_before_anything_is_written
    close("done")
    before = files_without_databases
    plan = Resources::SortPlan.new(folder, closed: Set["1"])

    assert_equal ["preview: would amend #{INTENT}/spec.md: link reviews/r1.md -> resources/tmp/reviews/r1.md; #{REASON}",
      "preview: would amend #{INTENT}/spec.md: link resources/notes.md -> resources/tmp/notes.md; #{REASON}"], plan.amendments.map(&:preview)
    assert_equal [before, []], [files_without_databases, amended]
  end
end
