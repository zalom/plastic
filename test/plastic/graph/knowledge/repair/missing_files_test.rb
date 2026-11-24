# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/graph/knowledge/repair/missing_files"

# The files the layout requires of a done or abandoned intent that its folder lacks. Done work is never written again,
# so each one is listed only; the list reads the required files from the layout, never from a list of its own.
class RepairMissingFilesTest < Plastic::TestCase
  MissingFiles = Plastic::Graph::Knowledge::Repair::MissingFiles
  DONE = "store/7--done"
  ABANDONED = "store/8--dropped"
  OPEN = "store/9--open"

  def setup
    super
    @folder = Plastic::Graph::Knowledge::StoreFolder.new(File.join(@home, "folder"))
    [DONE, ABANDONED, OPEN].each { |dir| @folder.write("#{dir}/spec.md", "# Spec\n") }
  end

  def required(state) = Plastic::Layout.required_in(state).map(&:name)

  def missing(dirs: [DONE, ABANDONED, OPEN], arriving: []) = MissingFiles.new(@folder, { "7" => "done", "8" => "abandoned" }, dirs:, arriving:)

  def fill(dir, names) = names.each { |name| @folder.write("#{dir}/#{name}", "x\n") }

  def test_a_done_intent_that_lacks_a_required_file_is_listed_with_the_reason
    fill(DONE, required("done") - ["outcome.md"])

    assert_equal ["missing #{DONE}/outcome.md: the layout requires it of a done intent; #{MissingFiles::WHY}"],
      missing(dirs: [DONE]).lines
  end

  def test_an_abandoned_intent_lists_each_file_its_state_requires
    listed = missing(dirs: [ABANDONED])

    assert_equal (required("abandoned") - ["spec.md"]).sort, listed.to_a.first.names.sort
    assert_includes listed.lines.first, "the layout requires it of an abandoned intent"
  end

  def test_an_open_intent_is_never_listed
    assert_empty missing(dirs: [OPEN]).to_a
  end

  def test_a_folder_with_every_required_file_is_not_listed
    fill(DONE, required("done"))

    assert_empty missing(dirs: [DONE]).to_a
  end

  def test_a_file_a_repair_moves_onto_the_required_path_counts_as_there
    fill(DONE, required("done") - ["intent.md"])

    assert_empty missing(dirs: [DONE], arriving: ["#{DONE}/intent.md"]).to_a
  end

  def test_only_the_folders_of_the_call_are_read
    assert_equal [ABANDONED], missing(dirs: [ABANDONED]).to_a.map(&:dir)
  end

  def test_the_states_are_the_done_and_abandoned_intents_of_the_store
    intents = [%w[7 done], %w[8 abandoned], %w[9 in_progress]].map { |id, status| Plastic::Graph::Knowledge::Intent.new(**Plastic::Graph::Knowledge::Intent.members.to_h { |key| [key, nil] }, intent_id: id, status:) }

    assert_equal({ "7" => "done", "8" => "abandoned" }, MissingFiles.states(intents))
  end

  def test_listing_writes_nothing
    before = snapshot(File.join(@home, "folder"))
    missing.lines

    assert_equal before, snapshot(File.join(@home, "folder"))
  end
end
