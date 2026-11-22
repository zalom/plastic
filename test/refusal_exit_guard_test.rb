# frozen_string_literal: true

require_relative "test_helper"

# A refusal is a rule that says no: a closed intent, a blocked or held node, a missing go-ahead, a thing that
# already exists. Every refusal exits 3, so a gate that names one stops as :refusal. A gate for a missing
# record, a bad input or a broken file stops as :failure, exit 1.
class RefusalExitGuardTest < Minitest::Test
  WORKFLOWS = File.expand_path("../lib/plastic/workflows", __dir__)
  GATE = /^\s*gate\b.*?(?=^\s*(?:gate|read|step|outcome|sets|def|forget_stop|open_intent_gates|review_round_gate)\b|\z)/m
  FAILURE = /stops: :failure/
  REFUSAL_WORDS = /already (?:exists|installed)|is archived|done or abandoned|not open or in progress|no longer be abandoned|only an intent in progress|a closed intent|has no go-ahead|is blocked|is held|capped|rounds? (?:is|are) used|session \S+ ended|not in progress|is %\{status\}|%\{(?:closed|session|approval)_problem\}|state of the node|state does not allow|node is not open|needs a node that is not done|is not archived/i

  def files = Dir.glob(File.join(WORKFLOWS, "**", "*.rb"))

  def failing_gates(text) = text.scan(GATE).select { |gate| gate.match?(FAILURE) && gate.match?(REFUSAL_WORDS) }

  def test_the_workflow_files_are_read_from_the_disk
    refute_empty files
  end

  def test_the_detector_catches_a_refusal_that_stops_as_a_failure
    sample = %(gate "intent %{intent_id} is archived", stops: :failure, offers: "plastic next",\n  pass: ->(context) { true }\n)

    refute_empty failing_gates(sample)
  end

  def test_the_detector_leaves_a_refusal_that_stops_as_a_refusal
    sample = %(gate "intent %{intent_id} is archived", stops: :refusal,\n  pass: ->(context) { true }\n)

    assert_empty failing_gates(sample)
  end

  def test_the_detector_leaves_a_missing_record_that_stops_as_a_failure
    sample = %(gate "no intent %{intent_id} in this store", stops: :failure, pass: ->(context) { true }\n)

    assert_empty failing_gates(sample)
  end

  def test_no_gate_that_names_a_refusal_stops_as_a_failure
    hits = files.flat_map { |path| failing_gates(File.read(path, encoding: "UTF-8")).map { |gate| "#{path.delete_prefix("#{WORKFLOWS}/")}: #{gate.strip.lines.first.strip}" } }

    assert_empty hits
  end
end
