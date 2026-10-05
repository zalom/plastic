# frozen_string_literal: true

require_relative "release_helper"

class InstallerReleaseBundleTest < Minitest::Test
  include ReleaseHelper

  RUBY = InstallerRelease::Ruby.new("/opt/plastic/rubies/4.0.7-jdx-2/bin/ruby")

  def test_installs_the_runtime_gems_into_the_release_standalone
    env, command = bundled.first
    runtime = File.join(@root, "release", "runtime")

    assert_equal %w[install --standalone], command[1, 2]
    assert_equal({ "BUNDLE_GEMFILE" => File.join(runtime, "Gemfile"), "BUNDLE_PATH" => File.join(runtime, "bundle"), "BUNDLE_FROZEN" => "true" },
      env.slice("BUNDLE_GEMFILE", "BUNDLE_PATH", "BUNDLE_FROZEN"))
  end

  def test_runs_the_bundle_program_beside_the_chosen_ruby
    env, command = bundled.first

    assert_equal "/opt/plastic/rubies/4.0.7-jdx-2/bin/bundle", command.first
    assert_equal "/opt/plastic/rubies/4.0.7-jdx-2/bin", env.fetch("PATH").split(File::PATH_SEPARATOR).first
  end

  def test_uses_the_bundler_of_the_chosen_ruby_and_no_outside_gems
    env, = bundled.first

    assert_equal({ "BUNDLE_VERSION" => "system", "GEM_HOME" => nil, "GEM_PATH" => nil }, env.slice("BUNDLE_VERSION", "GEM_HOME", "GEM_PATH"))
  end

  def test_skips_a_release_without_a_runtime_gemfile
    calls = []
    installed = InstallerRelease::Bundle.new(run: ->(*arguments) { calls << arguments }).call(@root, RUBY)

    refute installed
    assert_empty calls
  end

  def test_the_default_runner_raises_when_the_command_fails
    error = assert_raises(RuntimeError) { InstallerRelease::Bundle::RUN.call({}, ["false"]) }
    assert_match(/false/, error.message)
  end

  private

  def bundled
    calls = []
    InstallerRelease::Bundle.new(run: ->(env, command) { calls << [env, command] }).call(release_with_gemfile, RUBY)
    calls
  end

  def release_with_gemfile
    runtime = File.join(@root, "release", "runtime")
    FileUtils.mkdir_p(runtime)
    File.write(File.join(runtime, "Gemfile"), "source \"https://rubygems.org\"\n")
    File.dirname(runtime)
  end
end
