# frozen_string_literal: true

require_relative "../support/kernel"

class ReaderTest < Minitest::Test
  include KernelFixtures::StoreGraphs

  Reader = Plastic::Graph::Reader

  def reader(intents = retrieval.intents) = Reader.new(folder, intents.to_h { |intent| [intent.intent_id, intent] }, origin)

  def test_a_read_names_its_path_its_database_and_its_line
    open_intent
    write("store/1--alpha/spec.md", "# Spec\n")
    read = reader.read("store/1--alpha/spec.md")

    assert_equal ["store/1--alpha/spec.md", :knowledge, "read store/1--alpha/spec.md"], [read.path, read.database, read.line]
  end

  def test_index_json_reads_into_the_work_graph
    open_intent

    assert_equal :work, reader.read("store/index.json").database
  end

  def test_a_folder_with_no_intent_row_is_refused
    error = assert_raises(Plastic::Invalid) { reader.read("store/7--stray/spec.md") }

    assert_equal "store/7--stray has no intent row and no entry in store/index.json; add one or remove the folder", error.message
  end

  def test_a_folder_whose_slug_differs_from_the_row_is_refused
    open_intent

    assert_raises(Plastic::Invalid) { reader.read("store/1--other/spec.md") }
  end

  def test_a_kept_print_holds_the_hash_of_the_file_as_it_is
    open_intent
    write("store/1--alpha/savepoint.md", "")
    print = reader.read("store/1--alpha/savepoint.md").kept_print(folder)

    assert_equal ["store/1--alpha/savepoint.md", :work, Digest::SHA256.hexdigest(""), nil], print.to_h.values
  end
end
