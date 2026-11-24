# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "json"
require_relative "support/child_process"
require "tmpdir"

# The release archive carries a runtime Gemfile for the run-time gems, and the
# launcher loads the standalone bundle that activation builds beside it.
class RuntimeBundleTest < Minitest::Test
  REPO = File.expand_path("..", __dir__)

  def test_the_runtime_gemfile_names_sqlite3_and_tty_prompt
    gemfile = File.read(File.join(REPO, "runtime", "Gemfile"))

    assert_equal %w[sqlite3 tty-prompt], gemfile.scan(/^gem "([^"]+)"/).flatten
  end

  def test_the_runtime_lock_pins_the_development_sqlite3
    runtime = File.read(File.join(REPO, "runtime", "Gemfile.lock"))
    development = File.read(File.join(REPO, "Gemfile.lock"))
    version = development[/^    sqlite3 \((\d[^-)]*)/, 1]

    assert_includes runtime, "    sqlite3 (#{version}-arm64-darwin)"
    assert_includes runtime, "    sqlite3 (#{version}-x86_64-linux-gnu)"
  end

  def test_the_runtime_lock_still_lists_the_precompiled_sqlite3_of_every_platform
    runtime = File.read(File.join(REPO, "runtime", "Gemfile.lock"))
    platforms = %w[aarch64-linux-gnu arm64-darwin x86_64-darwin x86_64-linux-gnu]

    assert_equal platforms, platforms.select { |platform| runtime.include?("    sqlite3 (2.9.6-#{platform})") }
  end

  def test_the_runtime_lock_pins_the_development_tty_prompt
    runtime = File.read(File.join(REPO, "runtime", "Gemfile.lock"))
    development = File.read(File.join(REPO, "Gemfile.lock"))
    version = development[/^    tty-prompt \(([^)]+)\)/, 1]

    assert_includes runtime, "    tty-prompt (#{version})"
  end

  def test_the_runtime_lock_covers_every_platform_install_sh_pins_a_ruby_for
    runtime = File.read(File.join(REPO, "runtime", "Gemfile.lock"))
    platforms = runtime[/^PLATFORMS\n(.*?)\n\n/m, 1].split

    assert_equal %w[aarch64-linux-gnu arm64-darwin x86_64-darwin x86_64-linux], platforms.sort
    assert_includes runtime, "    sqlite3 (#{runtime[/sqlite3 \((\d[^-)]*)/, 1]}-x86_64-darwin)"
  end

  def test_the_runtime_lock_names_the_bundler_of_the_pinned_ruby
    runtime = File.read(File.join(REPO, "runtime", "Gemfile.lock"))

    assert_equal "4.0.20", runtime[/^BUNDLED WITH\n\s+(\S+)/, 1]
  end

  def test_the_package_ships_the_runtime_gemfile_and_version
    files = JSON.parse(File.read(File.join(REPO, "package.json"))).fetch("files")

    assert_includes files, "runtime/Gemfile"
    assert_includes files, "runtime/Gemfile.lock"
    assert_includes files, "VERSION"
  end

  def test_the_launcher_loads_the_standalone_bundle_when_it_exists
    Dir.mktmpdir("plastic-launcher") do |package|
      FileUtils.mkdir_p([File.join(package, "exe"), File.join(package, "runtime", "bundle", "bundler")])
      FileUtils.cp(File.join(REPO, "exe", "plastic"), File.join(package, "exe", "plastic"))
      File.write(File.join(package, "runtime", "bundle", "bundler", "setup.rb"), "puts \"bundle loaded\"\nexit 0\n")
      out, err, status = ChildProcess.capture3({ "HOME" => package }, RbConfig.ruby, "--disable-gems", File.join(package, "exe", "plastic"))

      assert_equal [0, "bundle loaded\n", ""], [status.exitstatus, out, err]
    end
  end

  def test_the_runtime_gemfile_names_irb_in_the_console_group
    gemfile = File.read(File.join(REPO, "runtime", "Gemfile"))

    assert_match(/^group :console do\n  gem "irb", "~> 1\.19"\nend$/, gemfile)
  end

  def test_the_development_gemfile_names_irb
    assert_match(/^gem "irb", "~> 1\.19"$/, File.read(File.join(REPO, "Gemfile")))
  end

  def test_the_runtime_lock_pins_the_development_irb
    runtime = File.read(File.join(REPO, "runtime", "Gemfile.lock"))
    development = File.read(File.join(REPO, "Gemfile.lock"))
    version = development[/^    irb \(([^)]+)\)/, 1]

    assert_includes runtime, "    irb (#{version})"
  end

  def test_the_standalone_bundle_loads_irb_without_rubygems
    skip "no standalone bundle is built in this checkout" unless File.file?(File.join(REPO, "runtime", "bundle", "bundler", "setup.rb"))

    out, err, status = ChildProcess.capture3({}, RbConfig.ruby, "--disable-gems", "-r", File.join(REPO, "runtime", "bundle", "bundler", "setup.rb"), "-e", "require 'irb'; print IRB::VERSION")

    assert_equal [0, "", true], [status.exitstatus, err, out.match?(/\A1\.\d+/)]
  end
end
