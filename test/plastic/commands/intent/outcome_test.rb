# frozen_string_literal: true

require_relative "../../../test_helper"

class IntentOutcomeCaseTest < Plastic::TestCase
  def test_an_outcome_without_a_file_exits_2
    ran("intent new Alpha")

    assert_case line("intent outcome 1"), code: 2, out: "", err: ["plastic: missing --from"]
  end
end

class IntentOutcomeTest < Plastic::TestCase
  def call(*args) = plastic("intent", "outcome", *args, table: Plastic::CLI::TABLE)

  def draft(text) = File.join(@home, "summary.md").tap { |path| File.write(path, text) }

  def body = retrieval.fetch("1", "outcome.md")&.body

  def test_a_summary_starts_the_outcome_of_an_intent_that_has_none
    open_intent

    result = call("1", "--from", draft("Shipped the command.\n"))

    assert_equal [0, ""], [result.code, result.err]
    assert_includes result.out, "outcome: written from #{File.join(@home, "summary.md")}"
    assert_equal "# Outcome\n\nShipped the command.\n", body
  end

  def test_a_summary_replaces_the_old_one_and_keeps_every_section
    intent = open_intent
    write("#{intent.dir}/outcome.md", "# Outcome\n\nOld words.\n\n## Verification\n\n- Pull request: 5\n\n## Notes\n\n- Report: r\n")
    sync_up

    call("1", "--from", draft("New words.\n\nA second paragraph.\n"))

    assert_equal "# Outcome\n\nNew words.\n\nA second paragraph.\n\n## Verification\n\n- Pull request: 5\n\n## Notes\n\n- Report: r\n", body
  end

  def test_a_summary_goes_above_the_sections_of_an_outcome_that_had_none
    open_intent
    plastic("intent", "note", "1", "first", table: Plastic::CLI::TABLE)

    call("1", "--from", draft("Summary.\n"))

    assert_equal "# Outcome\n\nSummary.\n\n## Notes\n\n- Note: first\n", body
  end

  def test_the_outcome_is_printed_and_leaves_a_work_log_line
    intent = open_intent

    call("1", "--from", draft("Summary.\n"))

    assert_equal body, File.read(store_path("#{intent.dir}/outcome.md"))
    assert_includes retrieval.structure.work_log("1").map(&:kind), "summarized"
  end

  def test_a_summary_that_holds_a_heading_fails_and_writes_nothing
    open_intent

    result = call("1", "--from", draft("Summary.\n\n## Verification\n\n- Merged: x\n"))

    assert_equal [1, nil], [result.code, body]
    assert_includes result.err, "the summary holds the heading '## Verification'"
  end

  def test_an_empty_summary_fails_and_writes_nothing
    open_intent

    result = call("1", "--from", draft("\n  \n"))

    assert_equal [1, nil], [result.code, body]
    assert_includes result.err, "the summary is empty"
  end

  def test_a_missing_file_fails_and_writes_nothing
    open_intent

    result = call("1", "--from", File.join(@home, "missing.md"))

    assert_equal [1, nil], [result.code, body]
    assert_includes result.err, "the summary file cannot be read"
  end

  def test_a_missing_intent_fails
    result = call("9", "--from", draft("Summary.\n"))

    assert_equal [1, true], [result.code, result.err.include?("no intent 9 in this store")]
  end

  %w[done abandoned].each do |status|
    define_method(:"test_a_#{status}_intent_refuses_a_new_summary_and_offers_next") do
      open_intent(status:)

      result = call("1", "--from", draft("Late words.\n"))

      assert_equal [3, nil], [result.code, body]
      assert_includes result.err, "intent 1 is #{status}; a closed intent keeps its outcome"
      assert_match(/^next: plastic next/, result.out)
    end
  end
end
