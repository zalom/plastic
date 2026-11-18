# frozen_string_literal: true

require_relative "../../../test_helper"

class KnowledgeReaderTest < Plastic::TestCase
  fixtures :alpha

  Reader = Plastic::Graph::Knowledge::Reader

  def reader(intents = retrieval.intents) = Reader.new(folder, intents.to_h { |intent| [intent.intent_id, intent] }, origin)

  def test_a_read_names_its_path_its_database_and_its_line
    write("store/1--alpha/spec.md", "# Spec\n")
    read = reader.read("store/1--alpha/spec.md", FixedClock::STAMP)

    assert_equal ["store/1--alpha/spec.md", "read store/1--alpha/spec.md"], [read.path, read.line]
  end

  def test_a_folder_with_no_intent_row_is_refused
    error = assert_raises(Plastic::Invalid) { reader.read("store/7--stray/spec.md", FixedClock::STAMP) }

    assert_equal "store/7--stray has no intent row and no entry in store/index.json; add one or remove the folder", error.message
  end

  def test_a_folder_whose_slug_differs_from_the_row_is_refused
    assert_raises(Plastic::Invalid) { reader.read("store/1--other/spec.md", FixedClock::STAMP) }
  end

  def test_a_kept_print_holds_the_hash_of_the_file_as_it_is
    write("store/1--alpha/savepoint.md", "")
    print = reader.read("store/1--alpha/savepoint.md", FixedClock::STAMP).kept_print(folder)

    assert_equal ["store/1--alpha/savepoint.md", Digest::SHA256.hexdigest(""), nil], print.to_h.values
  end

  def write_index(**parts) = write(Plastic::Graph::Knowledge::StoreFolder::INDEX, JSON.generate({ "intents" => [], "clusters" => [], "links" => [] }.merge(parts.transform_keys(&:to_s))))

  def run_read(read) = store_graphs.databases.fetch(:store).transaction { |batch| read.apply.call(batch) }

  def test_the_cluster_part_of_the_index_reads_its_clusters
    write_index(clusters: [{ "name" => "Core", "intents" => ["1"] }])
    run_read(reader.read(Plastic::Graph::Prints::ClusterPart::PATH, FixedClock::STAMP))

    assert_equal [%w[Core 1]], retrieval.clusters.map { |cluster| [cluster.name, cluster.intent_id] }
  end

  def test_the_link_part_of_the_index_reads_its_links_stamped_with_the_given_time
    write_index(links: [{ "from_ref" => "1", "to_ref" => "notes.md", "kind" => "source" }])
    run_read(reader.read(Plastic::Graph::Prints::LinkPart::PATH, FixedClock::STAMP))

    assert_equal [["notes.md", FixedClock::STAMP]], retrieval.links("1").map { |link| [link.to_ref, link.at] }
  end
end
