require "minitest/autorun"
require "open3"

class SelectUpdateTargetTest < Minitest::Test
  SCRIPT = File.expand_path("../../scripts/select-update-target", __FILE__)

  def select(current, tags_json)
    out, = Open3.capture2("ruby", SCRIPT, current, stdin_data: tags_json)
    out.strip
  end

  def test_alpha_up_to_date_yields_empty
    assert_equal "", select("1.0.0-alpha.12",
      '{"alpha":"1.0.0-alpha.12","latest":"0.0.1"}')
  end

  def test_alpha_newer_alpha
    assert_equal "1.0.0-alpha.14", select("1.0.0-alpha.12",
      '{"alpha":"1.0.0-alpha.14","latest":"0.0.1"}')
  end

  def test_alpha_prefers_beta_when_higher
    assert_equal "1.0.0-beta.1", select("1.0.0-alpha.12",
      '{"alpha":"1.0.0-alpha.14","beta":"1.0.0-beta.1","latest":"0.0.1"}')
  end

  def test_beta_never_sees_alpha
    assert_equal "1.0.0-beta.2", select("1.0.0-beta.1",
      '{"alpha":"1.1.0-alpha.9","beta":"1.0.0-beta.2","latest":"0.0.1"}')
  end

  def test_stable_only_follows_stable
    assert_equal "1.0.1", select("1.0.0",
      '{"alpha":"1.1.0-alpha.3","beta":"1.0.0-beta.5","latest":"1.0.1"}')
  end

  def test_release_beats_its_own_prereleases
    assert_equal "1.1.0", select("1.1.0-alpha.1",
      '{"alpha":"1.1.0-alpha.2","beta":"1.1.0-beta.1","latest":"1.1.0"}')
  end

  def test_lower_stable_is_not_a_downgrade_for_alpha
    assert_equal "1.1.0-alpha.2", select("1.1.0-alpha.1",
      '{"alpha":"1.1.0-alpha.2","latest":"1.0.0"}')
  end

  def test_malformed_json_yields_empty
    assert_equal "", select("1.0.0-alpha.12", "not json")
  end
end
