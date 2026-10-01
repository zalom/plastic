# frozen_string_literal: true

require_relative "../../test_helper"

class OriginTest < Plastic::TestCase
  # A home with no origin id yet, inside the test's own folder.
  def setup
    super
    @fresh = File.join(@home, "fresh")
    FileUtils.mkdir_p(@fresh)
  end

  def test_the_origin_is_made_once_and_kept
    first = Plastic::Graph::Origin.new(@fresh).id

    assert_match(/\A\h{8}\z/, first)
    assert_equal first, Plastic::Graph::Origin.new(@fresh).id
    assert_equal "#{first}\n", File.read(File.join(@fresh, "origin_id"))
  end

  def test_nothing_is_made_until_the_id_is_asked_for
    Plastic::Graph::Origin.new(@fresh)

    refute_path_exists File.join(@fresh, "origin_id")
  end

  def test_an_empty_origin_file_gets_a_new_id
    File.write(File.join(@fresh, "origin_id"), "\n")

    assert_match(/\A\h{8}\z/, Plastic::Graph::Origin.new(@fresh).id)
  end
end
