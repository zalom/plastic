require "minitest/autorun"
require "open3"
require "json"

class SelectUpdateTargetTest < Minitest::Test
  SCRIPT = File.expand_path("../../scripts/select-update-target", __FILE__)

  def select(current, releases)
    out, = Open3.capture2("ruby", SCRIPT, current, stdin_data: JSON.generate(releases))
    out.strip
  end

  def releases(*versions)
    versions.map { |v| {"tag_name" => "v#{v}", "draft" => false} }
  end

  def test_alpha_up_to_date_yields_empty
    assert_equal "", select("1.0.0-alpha.12", releases("1.0.0-alpha.12", "0.0.1"))
  end

  def test_alpha_newer_alpha
    assert_equal "1.0.0-alpha.14", select("1.0.0-alpha.12", releases("1.0.0-alpha.14", "0.0.1"))
  end

  def test_alpha_prefers_beta_when_higher
    assert_equal "1.0.0-beta.1", select("1.0.0-alpha.12", releases("1.0.0-alpha.14", "1.0.0-beta.1", "0.0.1"))
  end

  def test_beta_never_sees_alpha
    assert_equal "1.0.0-beta.2", select("1.0.0-beta.1", releases("1.1.0-alpha.9", "1.0.0-beta.2", "0.0.1"))
  end

  def test_stable_only_follows_stable
    assert_equal "1.0.1", select("1.0.0", releases("1.1.0-alpha.3", "1.0.0-beta.5", "1.0.1"))
  end

  def test_release_beats_its_own_prereleases
    assert_equal "1.1.0", select("1.1.0-alpha.1", releases("1.1.0-alpha.2", "1.1.0-beta.1", "1.1.0"))
  end

  def test_lower_stable_is_not_a_downgrade_for_alpha
    assert_equal "1.1.0-alpha.2", select("1.1.0-alpha.1", releases("1.1.0-alpha.2", "1.0.0"))
  end

  # Intent 310: the check-update selector on a 1.14.1 install never proposes the 2.0 alpha,
  # and on the alpha itself reads 2.0.0-alpha.1 as up to date.
  def test_stable_install_never_sees_the_new_major_alpha
    assert_equal "", select("1.14.1", releases("1.14.1", "2.0.0-alpha.1"))
  end

  def test_new_major_alpha_is_up_to_date_on_its_own_channel
    assert_equal "", select("2.0.0-alpha.1", releases("1.14.1", "2.0.0-alpha.1"))
    assert_equal "2.0.0-alpha.1", select("1.0.0-alpha.19", releases("1.14.1", "2.0.0-alpha.1"))
  end

  def test_malformed_json_yields_empty
    out, = Open3.capture2("ruby", SCRIPT, "1.0.0-alpha.12", stdin_data: "not json")

    assert_equal "", out.strip
  end

  # G5 (intent 391): a draft release must never be offered as an update target.
  def test_a_draft_release_is_never_the_target
    drafted = [{"tag_name" => "v9.9.9", "draft" => true}, {"tag_name" => "v1.0.0", "draft" => false}]

    assert_equal "1.0.0", select("0.9.0", drafted)
  end
end
