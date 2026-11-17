# frozen_string_literal: true

require "json"
require_relative "../../test_helper"

class RoutinePrintingTest < Plastic::TestCase
  include LifecycleHelper
  include HandEditHelper

  def row_counts
    %i[work knowledge].to_h { |key| [key, store_graphs.databases.fetch(key).row("SELECT COUNT(*) AS n FROM #{(key == :work) ? "approvals" : "document_revisions"}").fetch("n")] }
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

  def edited_spec
    intent = specified
    write("#{intent.dir}/spec.md", "#{keyed_spec}\nEdited.\n")
    "#{intent.dir}/spec.md"
  end

  def test_an_edited_spec_refuses_approve
    path = edited_spec

    assert_refused(cli("intent", "approve", "1"), path)
  end

  def test_an_edited_spec_refuses_approve_and_writes_no_approval_row
    edited_spec
    cli("intent", "approve", "1")

    assert_equal 0, store_graphs.databases.fetch(:work).row("SELECT COUNT(*) AS n FROM approvals").fetch("n")
  end

  def test_an_edited_spec_stays_as_written_after_a_refusal
    path = edited_spec
    cli("intent", "approve", "1")

    assert_includes File.read(store_path(path)), "Edited."
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

  def test_an_edited_savepoint_refuses_auto_and_leaves_the_intent_unstarted
    intent = specified
    cli("intent", "approve", "1")
    write("#{intent.dir}/savepoint.md", "by hand\n")
    result = cli("auto", "1")

    assert_refused(result, "#{intent.dir}/savepoint.md")
    refute_equal "in_progress", retrieval.intent("1").status
  end

  def test_an_edited_outcome_refuses_a_note_and_a_revise
    intent = specified
    write("#{intent.dir}/outcome.md", "# by hand\n")
    results = [cli("intent", "note", "1", "a line"), cli("intent", "revise", "1", "Beta", "--why", "because")]

    assert_equal [[1, 1], [true, true]], [results.map(&:code), results.map { |result| result.err.include?(refusal("#{intent.dir}/outcome.md")) }]
  end

  def test_an_edited_kept_file_refuses_every_printing_command_of_the_intent
    name = "#{specified.dir}/resources/kept.txt"
    keep_file(name, "kept\n")
    write(name, "edited\n")

    assert_refused(cli("intent", "approve", "1"), name)
  end

  def keep_file(name, bytes)
    store_graphs.databases.fetch(:references).transaction do |batch|
      batch.put(:sqlar, { name:, mode: 0o100644, mtime: 0, sz: bytes.bytesize, data: SQLite3::Blob.new(bytes), intent_id: "1", sha256: Digest::SHA256.hexdigest(bytes), origin_id: origin })
    end
    store_graphs.work.print_intent("1")
  end

  def test_a_dry_run_is_not_checked
    intent = specified
    write("#{intent.dir}/spec.md", "#{keyed_spec}\nEdited.\n")

    refute_includes cli("intent", "revise", "1", "Beta", "--why", "because", "--dry-run").err, "changed by hand"
  end
end

# The hand edit check compares a context file by its content, as it does the index.
class RoutinePrintingContextTest < Plastic::TestCase
  include LifecycleHelper
  include HandEditHelper

  def context_path
    intent = specified
    cli("intent", "discover", "1", "spec")
    path = "#{intent.dir}/context.json"
    flunk "discover printed no context.json" unless folder.exist?(path)
    path
  end

  def context_data(path) = JSON.parse(File.read(store_path(path)))

  def level_context?(path) = File.read(store_path(path)) == "#{JSON.pretty_generate(context_data(path))}\n"

  def test_a_re_indented_context_lets_approve_node_add_and_note_pass_and_is_printed_again
    path = context_path
    write(path, JSON.generate(context_data(path)))
    results = [cli("intent", "approve", "1"), cli("node", "add", "1", "Deliver", "--criterion", KEY), cli("intent", "note", "1", "a line")]
    found = results.map { |result| [result.code, level_context?(path)] }

    assert_equal [[0, true]] * 3, found, results.map(&:err).join
  end

  def edited_context
    path = context_path
    write(path, JSON.generate(context_data(path).merge("context" => { "hand" => true })))
    path
  end

  def test_a_context_with_other_content_than_its_rows_is_refused
    edited_context
    refused = cli("intent", "note", "1", "a line")

    assert_equal [1, "next: plastic sync up"], [refused.code, refused.out[/^next: .*$/]], refused.err
  end

  def test_sync_up_reads_a_context_with_other_content_into_its_rows
    path = edited_context
    named = cli("sync", "up")
    again = cli("intent", "note", "1", "a line")
    rows = JSON.parse(retrieval.contexts("1").first.data)

    assert_equal [0, 0, true, { "hand" => true }], [named.code, again.code, level_context?(path), rows], again.err
  end
end

class RoutinePrintingIndexTest < Plastic::TestCase
  include LifecycleHelper
  include HandEditHelper

  def test_an_edited_index_refuses_intent_new_with_no_intent_written
    open_intent
    write("store/index.json", "{}\n")
    result = cli("intent", "new", "Second")

    assert_refused(result, "store/index.json")
    assert_nil retrieval.intent("2")
  end

  def test_a_changed_index_that_was_never_printed_refuses_intent_new_with_no_intent_written
    write("store/index.json", "{}\n")
    result = cli("intent", "new", "First")

    assert_refused(result, "store/index.json")
    assert_nil retrieval.intent("1")
  end

  def compact_index
    write("store/index.json", JSON.generate(JSON.parse(File.read(store_path("store/index.json")))))
  end

  def printed_index = JSON.pretty_generate(JSON.parse(File.read(store_path("store/index.json")))) + "\n"

  def test_a_re_indented_index_lets_approve_pass_and_is_printed_again
    specified
    compact_index
    result = cli("intent", "approve", "1")

    assert_equal [0, true], [result.code, File.read(store_path("store/index.json")) == printed_index]
  end

  def test_a_re_indented_index_lets_intent_new_pass_and_is_printed_again
    open_intent
    compact_index
    result = cli("intent", "new", "Beta")

    assert_equal [0, true, "Beta"], [result.code, File.read(store_path("store/index.json")) == printed_index, retrieval.intent("2")&.title]
  end

  def test_an_index_that_was_never_printed_is_cleared_by_sync_up_and_intent_new_passes
    write("store/index.json", "{}\n")
    refused = cli("intent", "new", "First")
    named = cli("sync", "up")
    again = cli("intent", "new", "First")

    assert_equal [1, "next: plastic sync up", 0, 0], [refused.code, refused.out[/^next: .*$/], named.code, again.code], again.err
  end

  def add_imported_cluster
    data = JSON.parse(File.read(store_path("store/index.json")))
    write("store/index.json", JSON.generate(data.merge("clusters" => [{ "name" => "imported", "intents" => ["1"] }])))
  end

  def test_an_index_with_other_content_than_the_rows_is_refused_though_printed_before_and_sync_up_clears_it
    open_intent
    add_imported_cluster
    results = [cli("intent", "new", "Beta"), cli("sync", "up"), cli("intent", "new", "Beta")]

    assert_equal [1, 0, 0], results.map(&:code), results.last.err
    assert_includes File.read(store_path("store/index.json")), "imported"
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
    write("roadmaps/r1.md", folder.read("roadmaps/r1.md").sub(/^# .*/, "# By hand"))

    assert_refused(cli("roadmap", "open", "r1", "a"), "roadmaps/r1.md")
  end
end

# A refusal of the hand edit check names a command, and that command clears the refusal.
class RoutinePrintingWayOutTest < Plastic::TestCase
  include LifecycleHelper
  include HandEditHelper

  def note = cli("intent", "note", "1", "a line")

  def named_command(result) = result.out[/^next: plastic (.*)$/, 1].to_s.split

  # The refused call, the command it names, then the refused call again.
  def round_trip(call)
    refused = call.call
    named = cli(*named_command(refused))
    [refused.code, named.code, call.call.code]
  end

  def test_an_edited_intent_file_is_cleared_by_the_command_the_refusal_names
    write("#{specified.dir}/intent.md", "# by hand\n")

    assert_equal [1, 0, 0], round_trip(method(:note))
  end

  def test_an_edited_spec_is_cleared_by_the_command_the_refusal_names
    write("#{specified.dir}/spec.md", "#{keyed_spec}\nEdited.\n")

    assert_equal [1, 0, 0], round_trip(method(:note))
  end

  def test_an_edited_savepoint_is_cleared_by_the_command_the_refusal_names
    intent = specified
    cli("intent", "approve", "1")
    write("#{intent.dir}/savepoint.md", "by hand\n")

    assert_equal [1, 0, 0], round_trip(method(:note))
  end

  def test_an_edited_graph_that_reads_is_cleared_by_the_command_the_refusal_names
    path = "#{specified.dir}/graph.json"
    write(path, "#{File.read(store_path(path))}\n")

    assert_equal [1, 0, 0], round_trip(method(:note))
  end

  def junk_graph
    path = "#{specified.dir}/graph.json"
    write(path, "{\"hand\":true}\n")
    path
  end

  def test_a_graph_that_cannot_be_read_is_refused_with_the_reason_and_the_overwrite_that_prints_it_again
    path = junk_graph
    refused = note

    assert_equal [1, true, "next: plastic sync down --overwrite #{path}"], [refused.code, refused.err.include?("cannot be read"), refused.out[/^next: .*$/]], refused.err
  end

  def test_a_graph_that_cannot_be_read_is_cleared_by_the_command_the_refusal_names_and_printed_again
    path = junk_graph
    found = round_trip(method(:note))

    assert_equal [[1, 0, 0], false], [found, File.read(store_path(path)).include?("hand")]
  end

  def test_junk_in_another_intents_graph_is_cleared_in_the_two_steps_that_are_named
    intent = specified
    other = open_intent("Beta")
    write("#{other.dir}/graph.json", "{\"hand\":true}\n")
    write("#{intent.dir}/spec.md", "#{keyed_spec}\nEdited.\n")
    steps = followed(note, 2)

    assert_equal [%w[sync up], %w[sync down --overwrite] + ["#{other.dir}/graph.json"], 0], [steps[0], steps[1], note.code]
  end

  # The command each refusal names, run in turn `count` times.
  def followed(result, count)
    Array.new(count) do
      named = named_command(result)
      result = cli(*named)
      named
    end
  end

  # The refused call names sync up and says the file is printed again from its rows;
  # sync up names the file, prints it again and exits 0; the refused call then runs.
  def generated_round_trip(path, hand_text, call)
    refused = call.call
    up = cli("sync", "up")

    [refused.out[/^next: .*$/], refused.err.include?("read it into rows"), up.code, up.out.include?("read #{path}"), holds?(path, hand_text), call.call.code]
  end

  def holds?(path, text) = File.read(store_path(path)).include?(text)

  def test_a_hand_edited_roadmap_is_refused_with_sync_up_which_reads_it_into_rows_and_clears_the_refusal
    cli("roadmap", "new", "r1")
    write("roadmaps/r1.md", File.read(store_path("roadmaps/r1.md")).sub(/^title:.*$/, "title: by hand"))
    batch = -> { cli("roadmap", "batch", "r1", "1", "--title", "T", "--goal", "G", "--done", "d") }

    assert_equal ["next: plastic sync up", true, 0, true, true, 0], generated_round_trip("roadmaps/r1.md", "by hand", batch)
  end

  def test_a_hand_edited_context_json_is_refused_with_sync_up_which_reads_it_into_rows_and_clears_the_refusal
    intent = specified
    cli("intent", "discover", "1", "spec")
    path = "#{intent.dir}/context.json"
    write(path, JSON.generate(JSON.parse(File.read(store_path(path))).merge("context" => { "my_note" => "keep this" })))
    add = -> { cli("node", "add", "1", "T", "--criterion", KEY) }

    assert_equal ["next: plastic sync up", true, 0, true, true, 0], generated_round_trip(path, "my_note", add)
  end

  def test_a_bare_overwrite_of_sync_down_leaves_a_one_sided_hand_edit_alone
    path = "#{specified.dir}/spec.md"
    write(path, "#{keyed_spec}\nEdited.\n")
    result = cli("sync", "down", "--overwrite")

    assert_equal [0, true], [result.code, File.read(store_path(path)).include?("Edited.")], result.err
  end

  def test_an_overwrite_of_one_path_prints_it_from_its_rows_though_the_rows_did_not_change
    path = "#{specified.dir}/spec.md"
    write(path, "#{keyed_spec}\nEdited.\n")
    result = cli("sync", "down", "--overwrite", path)

    assert_equal [0, false], [result.code, File.read(store_path(path)).include?("Edited.")], result.err
  end
end
