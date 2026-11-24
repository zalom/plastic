# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../test_helpers/resources_homes"
require_relative "../../../lib/plastic/doctor"

class DoctorUnsortedStoresTest < Plastic::TestCase
  include ResourcesHomes

  Scope = Struct.new(:plastic_home, :projects)

  def checks = Plastic::Doctor::UnsortedStores.checks(Scope.new(@plastic_home, {}))

  def put(files)
    folder = Plastic::Graph::Knowledge::StoreFolder.new(File.join(@plastic_home, "stores", "global"))
    files.each { |rel, text| folder.write("#{INTENT}/#{rel}", text) }
  end

  def test_names_an_unsorted_store_and_the_command
    put(OLD_FILES)

    assert_equal [["resources global:", "#{MOVES.size} files are outside the resources layout", "plastic resources sort --project global"]], checks.map(&:to_a)
  end

  def test_a_sorted_store_is_no_finding
    put("spec.md" => "# Spec\n")

    assert_equal [["resources global:", "ok, every file is in the resources layout", nil]], checks.map(&:to_a)
  end

  def test_a_conflict_is_a_finding_that_names_the_target
    put("reviews/r1.md" => "a\n", "resources/tmp/reviews/r1.md" => "b\n")
    found = checks.first

    assert_includes found.value, "resources/tmp/reviews/r1.md"
    assert_equal "plastic resources sort --project global", found.repair
  end

  def test_a_file_directly_under_output_is_unsorted
    put("spec.md" => "# Spec\n", "resources/output/loose.md" => "x\n")

    assert_equal [["resources global:", "1 files are outside the resources layout", "plastic resources sort --project global"]], checks.map(&:to_a)
  end
end
