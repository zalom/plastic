require "minitest/autorun"
require "tmpdir"
require_relative "../bin/lib/context_budget"

class ContextBudgetLayoutTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)

  def test_real_install_and_benchmark_seed_share_the_new_layout
    Dir.mktmpdir("context-layout") do |dir|
      fixture = ContextBudget::Fixture.build(dir: dir, repo: REPO)
      root = File.join(fixture.plastic_home, "stores")

      assert_equal File.join(root, "global", "INDEX.md"), fixture.index
      assert_includes File.read(fixture.index), "a-global-intent-in-flight"
      assert_includes File.read(File.join(root, "fixture", "INDEX.md")), "a-project-intent-in-flight"
    end
  end
end
