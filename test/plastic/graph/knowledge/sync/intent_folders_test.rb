# frozen_string_literal: true

require_relative "../../../../test_helper"

class KnowledgeSyncIntentFoldersTest < Plastic::TestCase
  IntentFolders = Plastic::Graph::Knowledge::Sync::IntentFolders

  def page(id, title) = "---\nid: #{id.to_json}\nintent: #{title.to_json}\ncreated: #{STAMP.to_json}\n---\n"

  def folders = IntentFolders.new(folder, retrieval)

  def test_a_folder_with_no_row_gives_a_row_with_the_fields_of_its_intent_file
    write("store/2--beta/2--beta.md", page("2", "Beta"))
    intent = folders.intents.first

    assert_equal ["2", "beta", "Beta", "open", STAMP], [intent.intent_id, intent.slug, intent.title, intent.status, intent.opened_at]
  end

  def index_entry(**fields)
    { "intent_id" => "2", "origin_id" => "other", "parent_id" => nil, "ref" => nil, "slug" => "beta", "title" => "Beta", "kind" => "build",
      "status" => "parked", "disposition" => nil, "opened_at" => STAMP, "closed_at" => nil }.merge(fields.transform_keys(&:to_s))
  end

  def test_a_folder_listed_in_the_index_takes_its_fields_from_the_index
    write("store/2--beta/2--beta.md", page("2", "Beta"))
    write("store/index.json", JSON.generate({ "intents" => [index_entry(status: "done", closed_at: STAMP, disposition: "delivered")], "clusters" => [] }))
    intent = folders.intents.first

    assert_equal ["done", "build", "delivered", STAMP], [intent.status, intent.kind, intent.disposition, intent.closed_at]
  end

  def test_an_index_entry_for_another_folder_name_is_not_used
    write("store/2--beta/2--beta.md", page("2", "Beta"))
    write("store/index.json", JSON.generate({ "intents" => [index_entry(slug: "gamma")], "clusters" => [] }))

    assert_equal "open", folders.intents.first.status
  end

  def test_an_index_that_is_not_json_leaves_the_fields_of_the_intent_file
    write("store/2--beta/2--beta.md", page("2", "Beta"))
    write("store/index.json", "{not json")

    assert_equal "open", folders.intents.first.status
  end

  def test_a_folder_whose_intent_already_has_a_row_gives_no_row
    open_intent

    assert_empty folders.intents
  end

  def test_a_folder_with_no_intent_file_is_a_problem_with_its_name_and_reason
    write("store/7--stray/spec.md", "x\n")

    assert_equal ["store/7--stray: no intent file intent.md or 7--stray.md"], folders.problems
  end

  def test_an_intent_file_whose_id_differs_from_its_folder_is_a_problem
    write("store/2--beta/2--beta.md", page("5", "Beta"))

    assert_match(%r{\Astore/2--beta: its intent file does not parse}, folders.problems.first)
  end

  def test_an_intent_file_with_bytes_that_are_not_text_is_a_problem
    write("store/2--beta/2--beta.md", "\xFF\xFE\n".b)

    assert_equal ["store/2--beta: its intent file does not parse: it has no id, intent, created in its front matter"], folders.problems
  end

  def test_two_folders_with_one_number_are_each_named_with_the_other
    write("store/2--beta/2--beta.md", page("2", "Beta"))
    write("store/2--gamma/2--gamma.md", page("2", "Gamma"))

    assert_equal ["store/2--beta: its number 2 is also the number of store/2--gamma",
      "store/2--gamma: its number 2 is also the number of store/2--beta"], folders.problems
  end

  def test_the_unreadable_folders_are_listed_by_path
    write("store/7--stray/spec.md", "x\n")

    assert_equal ["store/7--stray"], folders.unreadable
  end
end
