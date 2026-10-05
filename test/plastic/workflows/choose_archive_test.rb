# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/workflows/choose_archive"

class ChooseArchiveTest < Plastic::TestCase
  def test_revert_selects_restoration
    assert_equal :revert, run_workflow(Plastic::Workflows::ChooseArchive, revert: true).first
  end

  def test_no_revert_selects_the_archive
    assert_equal :archive, run_workflow(Plastic::Workflows::ChooseArchive, revert: false).first
  end
end
