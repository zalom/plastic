# frozen_string_literal: true

require_relative "../../test_helper"

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

    [refused.out[/^next: .*$/], refused.err.include?("generated from rows"), up.code, up.out.include?("printed again from rows: #{path}"), holds?(path, hand_text), call.call.code]
  end

  def holds?(path, text) = File.read(store_path(path)).include?(text)

  def test_a_hand_edited_roadmap_is_refused_with_sync_up_which_prints_it_again_and_clears_the_refusal
    cli("roadmap", "new", "r1")
    write("roadmaps/r1.md", "# by hand\n")
    batch = -> { cli("roadmap", "batch", "r1", "1", "--title", "T", "--goal", "G", "--done", "d") }

    assert_equal ["next: plastic sync up", true, 0, true, false, 0], generated_round_trip("roadmaps/r1.md", "by hand", batch)
  end

  def test_a_hand_edited_context_json_is_refused_with_sync_up_which_prints_it_again_and_clears_the_refusal
    intent = specified
    cli("intent", "discover", "1", "spec")
    path = "#{intent.dir}/context.json"
    write(path, File.read(store_path(path)).sub("{", "{\n  \"my_note\": \"keep this\","))
    add = -> { cli("node", "add", "1", "T", "--criterion", KEY) }

    assert_equal ["next: plastic sync up", true, 0, true, false, 0], generated_round_trip(path, "my_note", add)
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
