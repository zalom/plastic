# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"
require_relative "../lib/cli_fixture"
require_relative "../../scripts/lib/cli"
require_relative "../../scripts/lib/cli/commands/hook"

class CliHookCommandTest < Minitest::Test
  Hook = Plastic::CLI::Commands::Hook

  def setup
    @dir = Dir.mktmpdir("plastic-cli-hook")
    @fixture = CliFixture.new(@dir)
    @calls = []
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def hook(*argv, status: 0)
    runner = lambda do |path|
      @calls << path
      status
    end
    Hook.call(argv, runner: runner, directory: "/nowhere", **@fixture.streams)
  end

  def launcher(event)
    File.expand_path("../../hooks/#{event}", __dir__)
  end

  def test_every_event_runs_its_launcher
    Hook::EVENTS.each { |event| hook(event) }

    assert_equal Hook::EVENTS.map { |event| launcher(event) }, @calls
  end

  def test_every_event_has_a_launcher_on_disk
    Hook::EVENTS.each { |event| assert_path_exists launcher(event) }
  end

  def test_the_launcher_status_is_returned_unchanged
    assert_equal 3, hook("stop", status: 3)
  end

  def test_nothing_is_printed_around_the_launcher
    hook("capture")

    assert_empty @fixture.printed
    assert_empty @fixture.warned
  end

  def test_the_package_root_override_moves_the_launcher
    runner = ->(path) { @calls << path && 0 }
    Hook.call(["close"], runner: runner, out: @fixture.out, err: @fixture.err,
      env: @fixture.env("PLASTIC_PACKAGE_ROOT" => "/pkg"), home: @fixture.home)

    assert_equal ["/pkg/hooks/close"], @calls
  end

  def test_an_unknown_event_exits_two
    assert_equal 2, hook("bogus")
  end

  def test_an_unknown_event_lists_the_events
    hook("bogus")

    Hook::EVENTS.each { |event| assert_includes @fixture.warned, event }
  end

  def test_an_unknown_event_never_runs_a_launcher
    hook("bogus")

    assert_empty @calls
  end

  def test_no_event_exits_two
    assert_equal 2, hook
  end

  def test_the_dispatcher_reaches_the_command
    assert_equal 2, Plastic::CLI.call(%w[hook bogus], directory: "/nowhere", **@fixture.streams)
  end
end
