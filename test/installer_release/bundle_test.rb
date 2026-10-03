# frozen_string_literal: true

require_relative "release_helper"

class InstallerReleaseBundleTest < Minitest::Test
  include ReleaseHelper

  def test_installs_the_runtime_gems_into_the_release_standalone
    release_path = release_with_gemfile
    calls = []
    InstallerRelease::Bundle.new(run: ->(env, command) { calls << [env, command] }).call(release_path)

    env, command = calls.first
    runtime = File.join(release_path, "runtime")

    assert_equal %w[bundle install --standalone], command.first(3)
    assert_equal({ "BUNDLE_GEMFILE" => File.join(runtime, "Gemfile"), "BUNDLE_PATH" => File.join(runtime, "bundle"), "BUNDLE_FROZEN" => "true" },
      env.slice("BUNDLE_GEMFILE", "BUNDLE_PATH", "BUNDLE_FROZEN"))
  end

  def test_skips_a_release_without_a_runtime_gemfile
    calls = []
    installed = InstallerRelease::Bundle.new(run: ->(*arguments) { calls << arguments }).call(@root)

    refute installed
    assert_empty calls
  end

  def test_the_default_runner_raises_when_the_command_fails
    error = assert_raises(RuntimeError) { InstallerRelease::Bundle::RUN.call({}, ["false"]) }
    assert_match(/false/, error.message)
  end

  private

  def release_with_gemfile
    runtime = File.join(@root, "release", "runtime")
    FileUtils.mkdir_p(runtime)
    File.write(File.join(runtime, "Gemfile"), "source \"https://rubygems.org\"\n")
    File.dirname(runtime)
  end
end
