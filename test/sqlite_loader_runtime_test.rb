# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../scripts/lib/plastic/graph/database/sqlite_loader"

class SqliteLoaderRuntimeTest < Minitest::Test
  Loader = Plastic::Graph::Database::SqliteLoader

  def test_loads_a_compatible_library_and_removes_a_failed_library_path
    with_library do |root, _library|
      without_sqlite3 do
        with_kernel_require(compatible_require) do
          assert Loader.fast_load([root])
          assert_equal "2.9.6", SQLite3::VERSION
        end
      end
    end
  end

  def test_removes_a_failed_library_path
    with_library do |root, library|
      without_sqlite3 do
        with_kernel_require(->(_name) { raise LoadError, "broken extension" }) { refute Loader.fast_load([root]) }
      end

      refute_includes $LOAD_PATH, library
    end
  end

  def test_uses_rubygems_fallback_and_rejects_a_wrong_loaded_version
    calls = []
    with_kernel_require(->(name) {
      calls << name
      true
    }) { Loader.fallback_load }

    assert_equal %w[rubygems sqlite3], calls
  end

  def test_rejects_a_wrong_loaded_version
    without_sqlite3 do
      define_sqlite("2.9.5")
      error = assert_raises(LoadError) { Loader.validate! }
      assert_includes error.message, "found 2.9.5"
    end
  end

  def test_load_reuses_an_already_loaded_compatible_sqlite_library
    without_sqlite3 do
      define_sqlite("2.9.6")

      with_kernel_require(->(name) { flunk "load! must not require #{name} when SQLite3 is already loaded" }) do
        assert_nil Loader.load!(roots: [])
      end
    end
  end

  def test_load_falls_back_after_a_fast_library_load_fails_and_removes_its_path
    with_library do |root, library|
      calls = []
      without_sqlite3 do
        with_kernel_require(fallback_require(calls)) { assert_nil Loader.load!(roots: [root]) }
      end

      assert_equal %w[sqlite3 rubygems sqlite3], calls
      refute_includes $LOAD_PATH, library
    end
  end

  def test_fast_load_skips_roots_without_a_compatible_sqlite_library
    Dir.mktmpdir("plastic-sqlite-loader") do |root|
      refute Loader.fast_load([root])
    end
  end

  def test_rejects_a_sqlite_library_built_for_another_platform
    Dir.mktmpdir("plastic-sqlite-loader") do |root|
      incompatible = write_library(root, "sqlite3-2.9.6-impossible-platform")

      assert_nil Loader.sqlite_load_path([root])
    ensure
      FileUtils.remove_entry(incompatible, true) if incompatible
    end
  end
end

module SqliteLoaderRuntimeFixtures
  private

  def write_library(root, name)
    path = File.join(root, "gems", name, "lib")
    FileUtils.mkdir_p(path)
    File.write(File.join(path, "sqlite3.rb"), "# fixture")
    path
  end

  def with_kernel_require(replacement)
    original = Kernel.instance_method(:require)
    Kernel.send(:define_method, :require, &replacement)
    yield
  ensure
    Kernel.send(:define_method, :require, original)
  end

  def without_sqlite3
    original = Object.const_get(:SQLite3) if defined?(SQLite3)
    Object.send(:remove_const, :SQLite3) if defined?(SQLite3)
    yield
  ensure
    Object.send(:remove_const, :SQLite3) if defined?(SQLite3)
    Object.const_set(:SQLite3, original) if original
  end

  def with_library
    Dir.mktmpdir("plastic-sqlite-loader") do |root|
      library = write_library(root, "sqlite3-2.9.6")
      yield root, library
    ensure
      $LOAD_PATH.delete(library) if library
    end
  end

  def define_sqlite(version)
    Object.const_set(:SQLite3, Module.new.tap { |sqlite| sqlite.const_set(:VERSION, version) })
  end

  def compatible_require
    define_library = method(:define_sqlite)
    ->(name) do
      define_library.call("2.9.6") if name == "sqlite3"
      true
    end
  end

  def fallback_require(calls)
    require_library = compatible_require
    ->(name) do
      calls << name
      raise LoadError, "broken extension" if calls == ["sqlite3"]

      require_library.call(name)
    end
  end
end

SqliteLoaderRuntimeTest.include(SqliteLoaderRuntimeFixtures)
