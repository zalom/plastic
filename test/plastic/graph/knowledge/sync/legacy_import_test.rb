# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeSyncLegacyImportTest < Plastic::TestCase
  fixtures :legacy

  def sync = Plastic::Graph::Knowledge::Sync.new(folder:, retrieval:, databases: store_graphs.databases)

  def import = Plastic::Graph::Knowledge::Sync::LegacyImport.new(sync, folder, retrieval, store_graphs.databases).call

  def test_the_import_says_what_it_read_and_keeps_index_md
    lines = import

    assert_equal "imported INDEX.md: 2 intents and 0 clusters", lines.first
    assert_includes lines, "read store/1--ai-infra/spec.md"
    assert_equal [true, true], [folder.exist?("INDEX.md"), folder.exist?("store/index.json")]
  end

  def test_the_intents_take_their_status_parent_and_front_matter
    import
    first, child = retrieval.intents

    assert_equal %w[1 active ai-infra], first.to_h.values_at(:intent_id, :status, :slug)
    assert_equal %w[1a 1 future], child.to_h.values_at(:intent_id, :parent_id, :status)
    refute_nil first.opened_at
  end

  def test_an_intent_with_no_own_file_imports_with_no_kind_or_date
    folder.delete("store/1a--litellm-proxmox-gateway/1a--litellm-proxmox-gateway.md")
    import

    assert_equal [nil, nil], retrieval.intent("1a").to_h.values_at(:kind, :opened_at)
  end

  def test_a_folder_with_no_entry_stops_the_import_before_any_write
    folder.write("store/9--stray/spec.md", "# Stray\n")
    error = assert_raises(Plastic::Invalid) { import }

    assert_includes error.message, "store/9--stray has no entry in INDEX.md"
    assert_equal [[], true], [retrieval.intents, folder.exist?("INDEX.md")]
  end

  def rows_of(sql) = store_graphs.databases.fetch(:knowledge).rows(sql)

  def test_a_first_import_keeps_plan_checklist_and_actions_in_legacy_rows
    import

    assert_equal %w[actions/.gitkeep checklist.md plan.md], rows_of("SELECT path FROM legacy_intents_data WHERE intent_id = '1' ORDER BY path").map { |row| row["path"] }
  end

  def test_a_first_import_keeps_the_plan_whole
    import
    body = rows_of("SELECT body FROM legacy_intents_data WHERE intent_id = '1' AND path = 'plan.md'").first["body"]

    assert_equal folder.read("store/1--ai-infra/plan.md").dup.force_encoding(Encoding::UTF_8), body
  end

  def test_a_first_import_leaves_the_other_files_as_documents
    import

    assert_equal %w[1--ai-infra.md outcome.md spec.md], rows_of("SELECT path FROM documents WHERE intent_id = '1' ORDER BY path").map { |row| row["path"] }
  end

  def test_the_import_metadata_line_names_the_legacy_files
    assert_includes import.last, "2 intents, 6 documents, 6 legacy files, 2 savepoint lines"
  end

  def test_a_sync_up_plan_on_a_legacy_store_imports_it
    assert_equal "imported INDEX.md: 2 intents and 0 clusters", sync.apply(sync.plan(:up, {})).first
  end
end
