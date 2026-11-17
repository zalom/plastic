# frozen_string_literal: true

require_relative "../../../../test_helper"
require_relative "../../../../../lib/plastic/workflows/code/init/choose"

class InitChooseTest < Plastic::TestCase
  Choose = Plastic::Workflows::Code::Init::Choose

  def choose(answer, installed: true, settings: FakeSettings.new)
    FileUtils.mkdir_p(File.join(@home, ".claude")) if installed
    context = call_context(declared: Choose.facts, harness: scoped_harness(env: { "PATH" => "" }), settings:, answer:)
    Choose.call(context)
    context
  end

  def test_a_home_with_no_harness_finds_none_and_reads_no_answer
    context = choose("a", installed: false)

    assert_equal [[], [], false], [context.found, context.picked, context.media]
  end

  def test_all_picks_every_harness_found_and_the_sync_of_media
    context = choose("a")

    assert_equal [["claude-code"], ["claude-code"], true], [context.found, context.picked, context.media]
  end

  def test_leaving_picks_nothing
    context = choose("q")

    assert_equal [["claude-code"], [], false], [context.found, context.picked, context.media]
  end

  def test_the_sync_of_media_is_not_picked_when_the_settings_turn_it_off
    settings = FakeSettings.new(values: { "sync.media" => false })

    assert_equal [false], [Choose.choices(scoped_harness(env: { "PATH" => "" }).scope, settings).last.chosen]
  end
end
