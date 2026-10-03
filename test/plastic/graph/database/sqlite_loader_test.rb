# frozen_string_literal: true

require "minitest/autorun"
require "open3"

class SqliteLoaderTest < Minitest::Test
  ROOT = File.expand_path("../../../..", __dir__)

  def test_loads_the_locked_sqlite_gem_without_rubygems
    out, err, status = subprocess("require 'plastic/graph/database/connection_pool'; puts SQLite3::VERSION; puts $LOADED_FEATURES.grep(/rubygems/).empty?")

    assert_predicate status, :success?, err
    assert_match(/\A2\.9\./, out)
    assert_includes out, "true"
  end

  def test_falls_back_to_rubygems_when_no_compatible_gem_root_exists
    out, err, status = subprocess("require 'plastic/graph/database/sqlite_loader'; Plastic::Graph::Database::SqliteLoader.load!(roots: []); puts SQLite3::VERSION; puts $LOADED_FEATURES.any? { |path| path.include?('rubygems') }")

    assert_predicate status, :success?, err
    assert_match(/\A2\.9\./, out)
    assert_includes out, "true"
  end

  private

  def subprocess(script)
    Open3.capture3("ruby", "--disable-gems", "-I", File.join(ROOT, "scripts", "lib"), "-e", script)
  end
end
