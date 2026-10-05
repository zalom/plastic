# encoding: UTF-8
# frozen_string_literal: true

require "minitest/autorun"

require_relative "../bin/lib/context_budget"

# PLASTIC.md stays under 200 lines, 1600 estimated tokens and 8192 bytes, so the
# suite stops it from growing back. CoreBudget measures through ContextBudget, the
# bench's estimator, so the two never disagree. Its predicates keep skill-lint's 500
# lines and 5000 tokens, and the byte predicate is the ruled 8192.
class CoreBudget
  Measurement = Struct.new(:lines, :tokens, :bytes) do
    def over_line_ceiling?
      lines >= 500
    end

    def over_token_ceiling?
      tokens >= 5000
    end

    def over_byte_ceiling?
      bytes >= 8192
    end
  end

  def self.measure(body)
    shared = ContextBudget.measure(body)
    Measurement.new(shared.lines, shared.tokens, shared.bytes)
  end
end

class PlasticCoreBudgetTest < Minitest::Test
  REPO = File.expand_path("../../", __FILE__)
  PLASTIC_MD = File.join(REPO, "PLASTIC.md")

  def live = CoreBudget.measure(File.read(PLASTIC_MD))

  def test_plastic_md_is_a_file_on_disk
    assert File.file?(PLASTIC_MD), "expected #{PLASTIC_MD} to exist"
  end

  def test_live_core_is_under_the_line_ceiling
    assert_operator live.lines, :<, 200, "PLASTIC.md is #{live.lines} lines; the ceiling is 200"
  end

  def test_live_core_is_under_the_token_ceiling
    assert_operator live.tokens, :<, 1600, "PLASTIC.md is about #{live.tokens} tokens; the ceiling is 1600"
  end

  def test_live_core_is_under_the_byte_ceiling
    assert_operator live.bytes, :<, 8192, "PLASTIC.md is #{live.bytes} bytes; the ceiling is 8192"
  end

  def test_core_budget_reports_the_shared_arithmetic
    body = File.read(PLASTIC_MD)
    shared = ContextBudget.measure(body)

    assert_equal [shared.lines, shared.tokens, shared.bytes], CoreBudget.measure(body).to_a
  end

  def test_the_line_predicate_trips_at_500_and_not_at_499
    assert_predicate CoreBudget::Measurement.new(500, 0, 0), :over_line_ceiling?
    refute_predicate CoreBudget::Measurement.new(499, 0, 0), :over_line_ceiling?
  end

  def test_the_token_predicate_trips_at_5000_and_not_at_4999
    assert_predicate CoreBudget::Measurement.new(0, 5000, 0), :over_token_ceiling?
    refute_predicate CoreBudget::Measurement.new(0, 4999, 0), :over_token_ceiling?
  end

  def test_the_byte_predicate_trips_at_8192_and_not_at_8191
    assert_predicate CoreBudget::Measurement.new(0, 0, 8192), :over_byte_ceiling?
    refute_predicate CoreBudget::Measurement.new(0, 0, 8191), :over_byte_ceiling?
  end

  def test_a_body_of_many_short_lines_trips_only_the_line_check
    trips = trips_of((["x"] * 600).join("\n"))

    assert_equal [true, false, false], trips
  end

  def test_a_body_of_many_words_trips_the_token_check_and_not_the_line_check
    trips = trips_of(([(["word"] * 40).join(" ")] * 100).join("\n"))

    assert_equal [false, true], trips.first(2)
  end

  def test_a_body_of_few_long_words_trips_only_the_byte_check
    trips = trips_of((["y" * 900] * 10).join("\n") + "\n")

    assert_equal [false, false, true], trips
  end

  private

  def trips_of(body)
    measurement = CoreBudget.measure(body)
    [measurement.over_line_ceiling?, measurement.over_token_ceiling?, measurement.over_byte_ceiling?]
  end
end

# The per-boot doctrine read is PLASTIC.md plus the installed decision tables,
# under 11,000 bytes: the ruled core ceiling, the fragment and some headroom.
class PlasticPerBootReadTest < Minitest::Test
  REPO = File.expand_path("../../", __FILE__)
  DOCTRINE_FILES = %w[PLASTIC.md skills/_decision-tables.md].freeze
  CEILING = 11_000

  def test_every_doctrine_file_exists
    DOCTRINE_FILES.each do |rel|
      assert File.file?(File.join(REPO, rel)), "expected #{rel} to exist"
    end
  end

  def test_per_boot_doctrine_read_is_under_the_ceiling
    sizes = DOCTRINE_FILES.map { |rel| [rel, File.size(File.join(REPO, rel))] }
    total = sizes.sum { |(_, size)| size }
    detail = sizes.map { |rel, size| "#{rel}=#{size}" }.join(", ")
    assert_operator total, :<, CEILING,
      "per-boot doctrine read is #{total} bytes (#{detail}); must stay under #{CEILING}"
  end
end
