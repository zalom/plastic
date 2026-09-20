# encoding: UTF-8
# frozen_string_literal: true

require_relative "../test_helper"
require "fileutils"
require "json"
require "stringio"
require "tmpdir"
require_relative "../../scripts/lib/cli/commands/version"

class CliVersionTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("plastic-cli-version")
    @out = StringIO.new
    @err = StringIO.new
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def version(*argv, root: @dir)
    Plastic::CLI::Commands::Version.new(argv, out: @out, err: @err,
      env: {"PLASTIC_PACKAGE_ROOT" => root}, home: "/nowhere")
  end

  def test_the_version_file_wins
    File.write(File.join(@dir, "VERSION"), "2.0.0-alpha.27\n")
    File.write(File.join(@dir, "package.json"), '{"version":"1.0.0"}')

    assert_equal 0, version.run
    assert_includes @out.string, "version  2.0.0-alpha.27"
  end

  def test_the_package_file_answers_when_there_is_no_version_file
    File.write(File.join(@dir, "package.json"), '{"version":"1.14.1"}')
    version.run

    assert_includes @out.string, "version  1.14.1"
  end

  def test_the_source_of_the_number_is_printed
    File.write(File.join(@dir, "VERSION"), "2.0.0\n")
    version.run

    assert_includes @out.string, "source   #{File.join(@dir, "VERSION")}"
  end

  def test_a_run_ends_with_a_next_step
    File.write(File.join(@dir, "VERSION"), "2.0.0\n")
    version.run

    assert_includes @out.string, "next: plastic status"
  end

  def test_no_version_anywhere_exits_one
    assert_equal 1, version.run
  end

  def test_no_version_anywhere_names_the_package_root
    version.run

    assert_includes @err.string, @dir
  end

  def test_a_package_file_without_a_version_key_exits_one
    File.write(File.join(@dir, "package.json"), '{"name":"@zalom/plastic"}')

    assert_equal 1, version.run
  end

  def test_a_malformed_package_file_exits_one_rather_than_raising
    File.write(File.join(@dir, "package.json"), "{not json")

    assert_equal 1, version.run
  end

  def test_the_package_root_falls_back_to_the_repository_this_file_sits_in
    command = Plastic::CLI::Commands::Version.new([], out: @out, err: @err, env: {}, home: "/nowhere")

    assert_equal 0, command.run
    assert_includes @out.string, "version  "
  end

  def test_json_carries_the_version_and_the_source
    File.write(File.join(@dir, "VERSION"), "2.0.0\n")
    version("--json").run

    assert_equal({"version" => "2.0.0", "source" => File.join(@dir, "VERSION")},
      JSON.parse(@out.string).fetch("result"))
  end
end
