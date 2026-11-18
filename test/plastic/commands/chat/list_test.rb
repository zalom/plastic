# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/chat/list"
require_relative "../../../../lib/plastic/graph/work/chat/writer"

class ChatListTest < Plastic::TestCase
  fixtures :empty

  ZoneClock = Struct.new(:now) do
    def local(*day) = Time.local(*day)
  end

  NOW = ZoneClock.new(Time.new(2026, 11, 17, 12, 0, 0, "+01:00"))

  def list(*args, clock: NOW) = plastic("chat", "list", *args, table: Plastic::CLI::TABLE, clock:)

  def record(store, at, text)
    clock = Struct.new(:now).new(at)
    Plastic::Graph::Work::Chat::Writer.new(store_graphs.databases.fetch(:local), store:, clock:).record(session_id: "s-1", harness: nil, intent_id: "7", role: "user", text:)
  end

  def lines(result) = result.out.lines(chomp: true).map { |line| line.squeeze(" ") }

  def test_lists_prompts_of_every_store_in_time_order
    FileUtils.mkdir_p(File.join(@plastic_home, "stores", "blog"))
    record("blog", Time.new(2026, 11, 17, 10, 0, 0, "+01:00"), "later")
    record("global", Time.new(2026, 11, 17, 9, 0, 0, "+01:00"), "earlier")
    texts = lines(list).grep(/earlier|later/)

    assert_equal [true, true], [texts.first.include?("earlier"), texts.last.include?("later")]
  end

  def test_since_leaves_out_older_prompts
    record("global", Time.new(2026, 11, 15, 9, 0, 0, "+01:00"), "stale")
    record("global", Time.new(2026, 11, 17, 9, 0, 0, "+01:00"), "fresh")
    out = list("--since", "2026-11-16").out

    assert_equal [false, true], [out.include?("stale"), out.include?("fresh")]
  end

  def test_a_date_without_a_zone_is_read_in_the_zone_of_the_clock
    in_zone("Europe/Berlin") do
      record("global", Time.new(2026, 11, 17, 0, 30, 0, "+01:00"), "just after midnight")

      assert_includes list("--since", "2026-11-17").out, "just after midnight"
    end
  end

  def in_zone(name)
    was = ENV.fetch("TZ", nil)
    ENV["TZ"] = name
    yield
  ensure
    ENV["TZ"] = was
  end

  def test_a_past_day_starts_at_midnight_of_that_day_across_a_change_of_summer_time
    in_zone("Europe/Berlin") do
      record("global", Time.utc(2026, 10, 19, 22, 30), "after midnight in summer time")
      record("global", Time.utc(2026, 10, 19, 21, 30), "before midnight in summer time")
      out = list("--since", "2026-10-20").out

      assert_equal [true, false], [out.include?("after midnight in summer time"), out.include?("before midnight in summer time")]
    end
  end

  def test_a_bad_date_is_usage_with_exit_2
    result = list("--since", "yesterday")

    assert_equal [2, true], [result.code, result.err.include?("--since")]
  end

  def test_names_a_store_it_cannot_read_and_still_lists_its_prompts
    record("gone", Time.new(2026, 11, 17, 9, 0, 0, "+01:00"), "orphaned prompt")
    result = list

    assert_equal [0, true, true], [result.code, result.out.include?("gone has no store folder"), result.out.include?("orphaned prompt")]
  end

  def test_no_prompts_says_so_and_offers_no_next
    result = list

    assert_equal [0, true, false], [result.code, result.out.include?("no prompts"), result.out.include?("next:")]
  end

  def test_it_writes_nothing
    record("global", Time.new(2026, 11, 17, 9, 0, 0, "+01:00"), "kept")
    list

    assert_equal 1, store_graphs.databases.fetch(:local).rows("SELECT id FROM chat_messages").size
  end
end
