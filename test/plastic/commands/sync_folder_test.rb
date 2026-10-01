# frozen_string_literal: true

require_relative "../support/kernel"

class SyncFolderTest < Minitest::Test
  include KernelFixtures::StoreCalls

  SAVEPOINT = "store/1--alpha/savepoint.md"

  def setup
    super
    run_plastic("intent", "new", "Alpha")
  end

  def test_a_folder_with_no_intent_row_is_refused
    FileUtils.mkdir_p(store_path("store/7--stray"))
    File.write(store_path("store/7--stray/spec.md"), "# Stray\n")
    call = run_plastic("sync", "up")

    assert_equal 1, call.code
    assert_includes call.err, "store/7--stray has no intent row and no entry in store/index.json"
  end

  def test_an_emptied_savepoint_drops_its_lines_and_keeps_its_file
    File.write(store_path(SAVEPOINT), "")
    calls = %w[up down].map { |direction| run_plastic("sync", direction) }

    assert_equal [0, 0], calls.map(&:code), calls.map(&:err).join
    assert_empty store_graphs.retrieval.savepoints("1")
    assert_equal "", File.read(store_path(SAVEPOINT))
  end
end
