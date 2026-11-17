# frozen_string_literal: true

require_relative "../../../test_helper"

class WorkNodeResultTest < Plastic::TestCase
  include LifecycleHelper

  def setup
    super
    specified
  end

  def dir = retrieval.intent("1").dir

  def result(files = []) = Plastic::Graph::Work::NodeResult.new(folder, retrieval).paths("1", files)

  def test_without_files_gives_every_changed_file_of_the_intent_folder
    write("#{dir}/a.md", "# a\n")
    write("#{dir}/b.md", "# b\n")

    assert_equal ["#{dir}/a.md", "#{dir}/b.md"], result
  end

  def test_with_files_gives_only_the_named_files
    write("#{dir}/a.md", "# a\n")
    write("#{dir}/b.md", "# b\n")

    assert_equal ["#{dir}/b.md"], result(["b.md"])
  end

  def test_a_file_named_by_its_path_in_the_store_is_the_same_file
    write("#{dir}/a.md", "# a\n")

    assert_equal ["#{dir}/a.md"], result(["#{dir}/a.md"])
  end

  def test_a_file_outside_the_intent_folder_is_refused_as_usage
    write("#{dir}/../elsewhere.md", "# elsewhere\n")

    assert_raises(Plastic::Usage) { result(["../elsewhere.md"]) }
  end

  def test_a_named_file_the_sync_does_not_read_is_refused_as_usage_naming_the_path
    write("#{dir}/resources/tmp/scratch.md", "# scratch\n")
    error = assert_raises(Plastic::Usage) { result(["resources/tmp/scratch.md"]) }

    assert_includes error.message, "resources/tmp/scratch.md"
  end

  def test_a_file_that_does_not_exist_is_refused_as_usage
    assert_raises(Plastic::Usage) { result(["ghost.md"]) }
  end

  def test_an_unchanged_file_is_left_out
    write("#{dir}/a.md", "# a\n")

    assert_equal [], result(["spec.md"])
    refute_includes result, "#{dir}/spec.md"
  end

  def test_legacy_files_are_left_out
    write("#{dir}/plan.md", "# plan\n")
    write("#{dir}/checklist.md", "# checklist\n")
    write("#{dir}/actions/one.md", "# one\n")
    write("#{dir}/a.md", "# a\n")

    assert_equal ["#{dir}/a.md"], result
  end

  def test_the_files_the_rows_print_are_left_out
    write("#{dir}/graph.json", "{\"hand\":true}")
    write("#{dir}/work.log", "by hand\n")

    assert_equal [], result
  end
end
