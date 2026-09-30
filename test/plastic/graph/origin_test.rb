# frozen_string_literal: true

require_relative "../support/kernel"

class OriginTest < Minitest::Test
  def setup = @home = Dir.mktmpdir("plastic-origin")

  def teardown = FileUtils.remove_entry(@home)

  def test_the_origin_is_made_once_and_kept
    first = Plastic::Graph::Origin.new(@home).id

    assert_match(/\A\h{8}\z/, first)
    assert_equal first, Plastic::Graph::Origin.new(@home).id
    assert_equal "#{first}\n", File.read(File.join(@home, "origin_id"))
  end

  def test_nothing_is_made_until_the_id_is_asked_for
    Plastic::Graph::Origin.new(@home)

    refute_path_exists File.join(@home, "origin_id")
  end
end
