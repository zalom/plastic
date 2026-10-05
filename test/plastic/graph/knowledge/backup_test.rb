# frozen_string_literal: true

require_relative "../../../test_helper"

class KnowledgeBackupTest < Plastic::TestCase
  def backup(sha256) = Plastic::Graph::Knowledge::Backup.from_h({ name: "a.tar.gz", sha256: })

  def archive(bytes)
    FileUtils.mkdir_p(File.join(@home, "backups"))
    File.write(File.join(@home, "backups", "a.tar.gz"), bytes)
  end

  def test_an_archive_that_matches_its_hash_has_no_flag
    archive("bytes")

    assert_nil backup(Digest::SHA256.hexdigest("bytes")).flag(@home)
  end

  def test_an_archive_that_no_longer_matches_is_flagged_changed
    archive("other")

    assert_equal "changed", backup(Digest::SHA256.hexdigest("bytes")).flag(@home)
  end

  def test_a_missing_archive_is_flagged_missing
    assert_equal "missing", backup("x").flag(@home)
  end
end
