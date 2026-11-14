# frozen_string_literal: true

require_relative "../../test_helper"

class RoutinePrintingTest < Plastic::TestCase
  include LifecycleHelper

  LINE = "%s changed by hand since the last print; run plastic sync up first"

  def refusal(path) = format(LINE, path)

  def row_counts
    %i[work knowledge].to_h { |key| [key, store_graphs.databases.fetch(key).row("SELECT COUNT(*) AS n FROM #{(key == :work) ? "approvals" : "document_revisions"}").fetch("n")] }
  end

  def assert_refused(result, path)
    assert_equal [1, true, true], [result.code, result.err.include?(refusal(path)), result.out.include?("next: plastic sync up")], result.err
  end

  def test_a_level_file_whose_bytes_equal_its_print_passes
    specified

    assert_equal 0, cli("intent", "approve", "1").code
  end

  def test_a_new_file_outside_the_prints_passes
    intent = specified
    write("#{intent.dir}/extra.md", "mine\n")

    assert_equal 0, cli("intent", "approve", "1").code
  end

  def test_an_edited_spec_refuses_approve_and_writes_no_approval_row
    intent = specified
    write("#{intent.dir}/spec.md", "#{keyed_spec}\nEdited.\n")
    result = cli("intent", "approve", "1")

    assert_refused(result, "#{intent.dir}/spec.md")
    assert_equal 0, store_graphs.databases.fetch(:work).row("SELECT COUNT(*) AS n FROM approvals").fetch("n")
    assert_includes File.read(store_path("#{intent.dir}/spec.md")), "Edited."
  end

  def test_an_edited_intent_file_refuses_a_note
    intent = specified
    write("#{intent.dir}/intent.md", "# by hand\n")
    before = row_counts
    result = cli("intent", "note", "1", "a line")

    assert_refused(result, "#{intent.dir}/intent.md")
    assert_equal [before, "# by hand\n"], [row_counts, File.read(store_path("#{intent.dir}/intent.md"))]
  end

  def test_an_edited_intent_file_refuses_a_rule
    intent = specified
    write("#{intent.dir}/intent.md", "# by hand\n")
    result = cli("intent", "rule", "1", "A ruling")

    assert_refused(result, "#{intent.dir}/intent.md")
    assert_equal "# by hand\n", File.read(store_path("#{intent.dir}/intent.md"))
  end

  def test_an_edited_savepoint_refuses_auto_and_writes_no_lock_row
    intent = specified
    cli("intent", "approve", "1")
    write("#{intent.dir}/savepoint.md", "by hand\n")
    result = cli("auto", "1")

    assert_refused(result, "#{intent.dir}/savepoint.md")
    assert_empty store_graphs.databases.fetch(:local).rows("SELECT * FROM locks")
  end

  def test_an_edited_outcome_refuses_a_note_and_a_revise
    intent = specified
    write("#{intent.dir}/outcome.md", "# by hand\n")
    results = [cli("intent", "note", "1", "a line"), cli("intent", "revise", "1", "Beta", "--why", "because")]

    assert_equal [[1, 1], [true, true]], [results.map(&:code), results.map { |result| result.err.include?(refusal("#{intent.dir}/outcome.md")) }]
  end

  def test_an_edited_kept_file_refuses_every_printing_command_of_the_intent
    intent = specified
    name = "#{intent.dir}/resources/kept.txt"
    bytes = "kept\n"
    store_graphs.databases.fetch(:references).transaction do |batch|
      batch.put(:sqlar, { name:, mode: 0o100644, mtime: 0, sz: bytes.bytesize, data: SQLite3::Blob.new(bytes), intent_id: "1", sha256: Digest::SHA256.hexdigest(bytes), origin_id: origin })
    end
    store_graphs.work.print_intent("1")
    write(name, "edited\n")

    assert_refused(cli("intent", "approve", "1"), name)
  end

  def test_a_dry_run_is_not_checked
    intent = specified
    write("#{intent.dir}/spec.md", "#{keyed_spec}\nEdited.\n")

    refute_includes cli("intent", "revise", "1", "Beta", "--why", "because", "--dry-run").err, "changed by hand"
  end

  def test_an_edited_index_refuses_intent_new_with_no_intent_written
    open_intent
    write("store/index.json", "{}\n")
    result = cli("intent", "new", "Second")

    assert_refused(result, "store/index.json")
    assert_nil retrieval.intent("2")
  end

  def open_roadmap
    cli("roadmap", "new", "r1")
    cli("roadmap", "batch", "r1", "1", "--title", "T", "--goal", "Batch goal", "--done", "batch done")
    cli("roadmap", "add", "r1", "1", "a", "--title", "A", "--goal", "Item goal", "--done", "item done")
  end

  def test_an_edited_index_refuses_roadmap_open
    open_intent
    open_roadmap
    write("store/index.json", "{}\n")

    assert_refused(cli("roadmap", "open", "r1", "a"), "store/index.json")
  end

  def test_an_edited_roadmap_file_refuses_roadmap_open
    open_roadmap
    write("roadmaps/r1.md", "# by hand\n")

    assert_refused(cli("roadmap", "open", "r1", "a"), "roadmaps/r1.md")
  end
end
