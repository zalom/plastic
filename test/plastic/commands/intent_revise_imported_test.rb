# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/intent_revise"

class IntentReviseImportedTest < Plastic::TestCase
  def call(*args) = plastic("intent", "revise", *args, table: Plastic::CLI::TABLE)

  def test_an_imported_folder_keeps_its_own_file_through_a_revise
    page = "---\nid: \"2\"\nintent: \"Beta\"\ncreated: \"#{STAMP}\"\n---\n\n# 2 - Beta\n"
    write("store/2--beta/2--beta.md", page)
    plastic("sync", "up", table: Plastic::CLI::TABLE)

    result = call("2", "Beta, revised")
    rows = store_graphs.databases.fetch(:knowledge).rows("SELECT path FROM documents WHERE intent_id = :id AND path LIKE :like", id: "2", like: "%beta.md")

    assert_equal 0, result.code, result.err
    assert_equal ["2--beta.md"], rows.map { |row| row.fetch("path") }
  end
end
