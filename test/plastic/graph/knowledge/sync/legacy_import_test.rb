# frozen_string_literal: true

require "delegate"
require_relative "../../../../test_helper"

class KnowledgeSyncLegacyImportTest < Plastic::TestCase
  fixtures :legacy

  def sync = Plastic::Graph::Knowledge::Sync.new(folder:, retrieval:, databases: store_graphs.databases)

  def import = Plastic::Graph::Knowledge::Sync::LegacyImport.new(sync, folder, retrieval, store_graphs.databases).call

  def test_the_import_says_what_it_read_and_keeps_index_md
    lines = import

    assert_equal "imported INDEX.md: 2 intents and 0 clusters", lines.first
    assert_includes lines, "read store/1--alpha-service/spec.md"
    assert_equal [true, true], [folder.exist?("INDEX.md"), folder.exist?("store/index.json")]
  end

  def test_the_intents_take_their_status_parent_and_front_matter
    import
    first, child = retrieval.intents

    assert_equal %w[1 active alpha-service], first.to_h.values_at(:intent_id, :status, :slug)
    assert_equal %w[1a 1 future], child.to_h.values_at(:intent_id, :parent_id, :status)
    refute_nil first.opened_at
  end

  def test_an_intent_with_no_own_file_imports_with_no_kind_or_date
    folder.delete("store/1a--beta-route/1a--beta-route.md")
    import

    assert_equal [nil, nil], retrieval.intent("1a").to_h.values_at(:kind, :opened_at)
  end

  def test_a_folder_with_no_entry_stops_the_import_before_any_write
    folder.write("store/9--stray/spec.md", "# Stray\n")
    error = assert_raises(Plastic::Invalid) { import }

    assert_includes error.message, "store/9--stray has no entry in INDEX.md"
    assert_equal [[], true], [retrieval.intents, folder.exist?("INDEX.md")]
  end

  def files_and_bytes = Dir.glob("**/*", File::FNM_DOTMATCH, base: folder.root).select { |rel| folder.exist?(rel) }.sort.to_h { |rel| [rel, folder.read(rel)] }

  def break_the_store
    folder.write("roadmaps/r1.md", "# R1\n\n## Batches\n\n### Batch 1 — A\n- [ ] 7 No status here\n")
    folder.write("INDEX.md", "#{folder.read("INDEX.md").force_encoding(Encoding::UTF_8)}\n- [3 — Gone](store/3--gone/3--gone.md)\n")
    folder.write("store/9--stray/spec.md", "# Stray\n")
    folder.write("store/1--alpha-service/graph.json", "{not json")
  end

  def test_the_check_pass_names_every_problem_of_the_store_in_one_error
    break_the_store
    message = assert_raises(Plastic::Invalid) { import }.message

    ["roadmaps/r1.md", "store/3--gone is in INDEX.md and has no folder", "store/9--stray has no entry in INDEX.md", "store/1--alpha-service/graph.json"].each do |named|
      assert_includes message, named
    end
  end

  def test_a_failed_check_leaves_no_database_no_index_and_every_file_as_it_was
    break_the_store
    retrieval.intents
    before = files_and_bytes
    assert_raises(Plastic::Invalid) { import }

    assert_equal before, files_and_bytes
    assert_empty retrieval.intents
    refute folder.exist?("store/index.json")
  end

  def test_a_file_that_cannot_be_read_is_a_problem_of_the_check_pass
    path = folder.path("store/1--alpha-service/plan.md")
    File.chmod(0o000, path)
    message = assert_raises(Plastic::Invalid) { import }.message
    File.chmod(0o644, path)

    assert_includes message, "store/1--alpha-service/plan.md"
  end

  def test_an_unlisted_folder_takes_the_status_of_its_front_matter
    folder.write("store/2--extra/2--extra.md", "---\nid: \"2\"\nintent: \"Extra work\"\nstatus: parked\ncreated: 2026-09-18\n---\n\n# Extra\n")
    import

    assert_equal %w[2 parked], retrieval.intent("2").to_h.values_at(:intent_id, :status)
  end

  def test_the_import_says_which_intent_it_has_written_after_each
    lines = import
    progress = lines.select { |line| line.start_with?("imported intent ") }

    assert_equal ["imported intent 1 of 2: 1", "imported intent 2 of 2: 1a"], progress
  end

  def test_progress_lines_sit_between_the_first_and_the_last_line
    lines = import

    assert_equal ["imported INDEX.md", "imported metadata"], [lines.first[/\Aimported INDEX\.md/], lines.last[/\Aimported metadata/]]
    refute_includes [lines.first, lines.last].map { |line| line.start_with?("imported intent ") }, true
  end

  # A reader that fails on its second call, the second intent.
  class FailsOnSecondRead < SimpleDelegator
    def read(paths)
      @reads = @reads.to_i + 1
      raise "disk failed" if @reads == 2

      super
    end
  end

  def test_a_read_that_fails_on_the_second_intent_leaves_no_database_and_the_folder_as_it_was
    retrieval.intents
    before = files_and_bytes
    failing = FailsOnSecondRead.new(sync)
    error = assert_raises(Plastic::Invalid) { Plastic::Graph::Knowledge::Sync::LegacyImport.new(failing, folder, retrieval, store_graphs.databases).call }

    assert_includes error.message, "disk failed"
    assert_equal before, files_and_bytes
    assert_empty retrieval.intents
  end

  def rows_of(sql) = store_graphs.databases.fetch(:knowledge).rows(sql)

  def test_a_first_import_keeps_plan_checklist_and_actions_in_legacy_rows
    import

    assert_equal %w[actions/.gitkeep checklist.md plan.md], rows_of("SELECT path FROM legacy_intents_data WHERE intent_id = '1' ORDER BY path").map { |row| row["path"] }
  end

  def test_a_first_import_keeps_the_plan_whole
    import
    body = rows_of("SELECT body FROM legacy_intents_data WHERE intent_id = '1' AND path = 'plan.md'").first["body"]

    assert_equal folder.read("store/1--alpha-service/plan.md").dup.force_encoding(Encoding::UTF_8), body
  end

  def test_a_first_import_leaves_the_other_files_as_documents
    import

    assert_equal %w[1--alpha-service.md outcome.md spec.md], rows_of("SELECT path FROM documents WHERE intent_id = '1' ORDER BY path").map { |row| row["path"] }
  end

  def test_the_import_metadata_line_names_the_legacy_files
    assert_includes import.last, "2 intents, 6 documents, 6 legacy files, 2 savepoint lines"
  end

  def test_a_sync_up_plan_on_a_legacy_store_imports_it
    assert_equal "imported INDEX.md: 2 intents and 0 clusters", sync.apply(sync.plan(:up, {})).first
  end

  def test_a_printed_context_json_is_not_imported_as_a_document
    folder.write("store/1--alpha-service/context.json", "{}")
    import

    assert_empty rows_of("SELECT * FROM documents WHERE path = 'context.json'")
    refute_includes rows_of("SELECT path FROM legacy_intents_data").map { |row| row["path"] }, "context.json"
  end
end
