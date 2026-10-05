# frozen_string_literal: true

require_relative "support/install_sh_helper"

class InstallShDependencyTest < Minitest::Test
  include InstallShHelper

  BASE_TOOLS = %w[mktemp rm mkdir ln cat cp uname dirname basename].freeze

  def test_names_each_missing_tool_with_both_platforms
    path = minimal_path(%w[tar])
    _out, err, status = Open3.capture3({ "HOME" => @home, "PATH" => path }, "/bin/sh", SCRIPT)

    assert_equal 1, status.exitstatus
    assert_empty ["needs curl", "needs sha256sum or shasum", "macOS:", "Linux:"].reject { |text| err.include?(text) }, err
  end

  def test_asks_for_no_ruby_and_no_bundler
    path = minimal_path(%w[tar])
    _out, err, = Open3.capture3({ "HOME" => @home, "PATH" => path }, "/bin/sh", SCRIPT)

    refute_match(/Ruby|Bundler/, err)
  end

  private

  def minimal_path(tools)
    minbin = File.join(@dir, "minbin")
    FileUtils.mkdir_p(minbin)
    (BASE_TOOLS + tools).each { |tool| File.symlink(which(tool), File.join(minbin, tool)) }
    minbin
  end

  def which(tool)
    ENV.fetch("PATH").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, tool) }.find { |path| File.executable?(path) }
  end
end
