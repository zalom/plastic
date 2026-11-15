# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/plastic/workflows/release_update"

class ReleaseUpdateTest < Plastic::TestCase
  # A release source whose download writes the archive and then stops.
  class HalfwaySource
    def files(_version, directory)
      File.write(File.join(directory, "plastic.tgz"), "half")
      raise Errno::ENOENT, "plastic.tgz.sha256"
    end
  end

  def test_a_download_that_stops_halfway_leaves_the_download_folder_gone
    share = File.join(@home, "share")
    update = Plastic::Workflows::ReleaseUpdate.new(share, HalfwaySource.new)

    assert_raises(Errno::ENOENT) { update.download("99.0.0") }
    refute_path_exists File.join(share, "download")
  end
end
