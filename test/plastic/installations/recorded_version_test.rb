# frozen_string_literal: true

require_relative "../../test_helper"
require "plastic/installations/recorded_version"

class RecordedVersionTest < Plastic::TestCase
  def recorded = Plastic::Installations::RecordedVersion.new(File.join(@home, "agent", "plastic"))

  def test_nothing_is_installed_before_a_version_is_written
    assert_equal [false, nil], [recorded.installed?, recorded.read]
  end

  def test_a_written_version_reads_back_and_the_write_returns_the_file
    path = recorded.write("2.0.3")

    assert_equal [File.join(@home, "agent", "plastic", "VERSION"), true, "2.0.3"], [path, recorded.installed?, recorded.read]
  end
end
