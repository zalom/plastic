require "minitest/autorun"

# G5 (intent 391): hooks/check-update reads the GitHub releases list through curl,
# never npm. Source-text check (matrix row "check-update hook"): the script names curl
# and the releases URL, and never names npm.
class CheckUpdateHookTest < Minitest::Test
  SOURCE = File.read(File.expand_path("../hooks/check-update", __dir__))

  def test_names_curl
    assert_match(/curl/, SOURCE)
  end

  def test_names_the_github_releases_url
    assert_match(%r{https://api\.github\.com/repos/zalom/plastic/releases}, SOURCE)
  end

  def test_never_names_npm
    refute_match(/npm/, SOURCE)
  end
end
