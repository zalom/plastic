# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../test_helpers/resources_homes"
require_relative "../../../../lib/plastic/commands/resources/sort"

class ResourcesSortCommandTest < Plastic::TestCase
  include ResourcesHomes

  fixtures :alpha_synced

  def setup
    super
    write_old_layout
  end

  def sort(*args) = plastic("resources", "sort", "--store", "global", *args, table: Plastic::CLI::TABLE)

  def test_the_preview_lists_the_links_that_would_change_and_the_links_left_alone
    out = sort("--dry-run").out

    assert_includes out, "preview: link would change #{INTENT}/spec.md: reviews/r1.md -> resources/tmp/reviews/r1.md"
    assert_includes out, "preview: link left as it is #{INTENT}/resources/notes.md: missing.md"
  end

  def test_the_preview_names_each_report_move_once_in_preview_words
    write("#{INTENT}/resources/output/reports/old.html", "<p>old</p>\n")
    lines = sort("--dry-run").out.lines.grep(/old\.html/)

    assert_equal ["preview: move #{INTENT}/resources/output/reports/old.html -> #{INTENT}/resources/tmp/old.html: neither recorded nor mandatory\n"], lines
  end

  def test_the_real_run_prints_the_links_it_changed_and_the_links_it_left_alone
    out = sort.out

    assert_includes out, "link changed #{INTENT}/spec.md: reviews/r1.md -> resources/tmp/reviews/r1.md"
    assert_includes out, "link left as it is #{INTENT}/resources/notes.md: missing.md"
  end

  def test_the_preview_of_a_done_intent_shows_each_amendment_and_writes_no_log_line
    store_database.transaction { |batch| batch.write(:intents, "UPDATE intents SET status = 'done' WHERE intent_id = '1'") }
    out = sort("--dry-run").out

    assert_includes out, "preview: would amend #{INTENT}/spec.md: link reviews/r1.md -> resources/tmp/reviews/r1.md; the resource sort moved its target"
    assert_equal 0, store_database.rows("SELECT count(*) AS n FROM work_log WHERE kind = 'amended'").first.fetch("n")
  end

def test_the_command_says_it_writes_amended_work_log_lines
  command = Plastic::Commands::Resources::Sort

  assert_includes command.changes.fetch(:work), "amended work log line"
  assert_includes command.options.find { |option| option.name == :dry_run }.text, "amendments"
end

def test_a_second_run_says_there_is_nothing_to_move
    sort

    assert_includes sort.out, "sorted: nothing to move"
  end
end
