# frozen_string_literal: true

require_relative "../../../test_helper"
require_relative "../../../../lib/plastic/commands/intent/spec"

class IntentSpecCaseTest < Plastic::TestCase
  def test_the_spec_of_a_missing_intent_exits_1_and_names_it
    assert_case line("intent spec 9"), code: 1, out: "", err: ["no intent 9 in this store"]
  end
end

class IntentSpecTest < Plastic::TestCase
  def call(*args) = plastic("intent", "spec", *args, table: Plastic::CLI::TABLE)

  def write_spec(intent, text)
    write("#{intent.dir}/spec.md", text)
    plastic("store", "sync", "up", table: Plastic::CLI::TABLE)
  end

  def test_the_grilling_method_always_prints
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Done criteria\n- ships\n")

    result = call(intent.intent_id)

    assert_includes result.out, "# The grilling"
  end

  def test_the_spec_line_shows_one_example_criterion
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Done criteria\n- ships\n")

    assert_includes call(intent.intent_id).out, "spec: the done criteria are the bullets under its \"## Done criteria\" heading, each written - [c1] text"
  end

  def test_an_open_decision_is_printed
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Open Questions\n- which store wins\n")

    result = call(intent.intent_id)

    assert_equal [0, "# The grilling", ""], [result.code, result.out.lines.first.chomp, result.err]
    assert_includes result.out, "open: which store wins"
    assert_includes result.out, "next: plastic intent rule #{intent.intent_id} TEXT"
  end

  def test_a_clear_spec_without_a_go_ahead_offers_no_command_and_says_who_approves
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Done criteria\n- ships\n")

    result = call(intent.intent_id)

    refute_match(/^next: /, result.out)
    assert_call result, code: 0, err: "", out: ["because: the spec is settled and has no go-ahead; in guided work the owner gives it, " \
      "and in auto the agents run plastic intent approve 1"]
  end

  def test_a_clear_spec_with_a_go_ahead_offers_the_brief
    intent = open_intent
    write_spec(intent, "# Spec\n\n## Done criteria\n- ships\n")
    plastic("intent", "approve", intent.intent_id, table: Plastic::CLI::TABLE)

    result = call(intent.intent_id)

    assert_equal "# The grilling", result.out.lines.first.chomp
    refute_includes result.out, "open:"
    assert_call result, code: 0, err: "", out: ["next: plastic intent brief #{intent.intent_id}"]
  end

  def test_no_spec_misses_no_open_decision
    intent = open_intent

    result = call(intent.intent_id)

    assert_equal [0, "# The grilling", ""], [result.code, result.out.lines.first.chomp, result.err]
    refute_includes result.out, "open:"
    assert_includes result.out, "next: plastic intent spec #{intent.intent_id} --from FILE"
  end
end

class IntentSpecFromTest < Plastic::TestCase
  SPEC = "# Spec\n\n## Goal\n\nShip it.\n\n## Done criteria\n\n- [c1] it ships\n\n## Open decisions\n\nNone.\n\n## Constraints\n\n- no network\n"

  def call(*args) = plastic("intent", "spec", *args, table: Plastic::CLI::TABLE)

  def draft(text = SPEC) = File.join(@home, "draft.md").tap { |path| File.write(path, text) }

  def body = retrieval.fetch("1", "spec.md")&.body

  def test_a_spec_from_a_file_is_written_as_the_spec_of_the_intent
    open_intent

    result = call("1", "--from", draft)

    assert_equal [0, ""], [result.code, result.err]
    assert_equal SPEC, body
  end

  def test_a_spec_from_a_file_says_what_was_written_and_prints_the_file
    intent = open_intent

    result = call("1", "--from", draft)

    assert_includes result.out, "spec: written from #{draft}"
    assert_equal SPEC, File.read(store_path("#{intent.dir}/spec.md"))
  end

  def test_a_spec_from_a_file_leaves_a_work_log_line
    open_intent

    call("1", "--from", draft)

    assert_includes retrieval.structure.work_log("1").map(&:kind), "specified"
  end

  def test_a_spec_that_names_its_sections_by_their_older_names_is_written
    open_intent
    text = SPEC.sub("## Done criteria", "## Acceptance Criteria").sub("## Open decisions", "## Open Questions")

    result = call("1", "--from", draft(text))

    assert_equal [0, text], [result.code, body]
  end

  def test_a_spec_that_lacks_a_section_of_the_layout_fails_and_writes_nothing
    open_intent

    result = call("1", "--from", draft("# Spec\n\n## Goal\n\nShip it.\n\n## Done criteria\n\n- [c1] it ships\n"))

    assert_equal [1, nil], [result.code, body]
    assert_includes result.err, "the spec lacks the sections Open decisions and Constraints"
  end

  def test_a_spec_from_a_missing_file_fails_and_writes_nothing
    open_intent

    result = call("1", "--from", File.join(@home, "missing.md"))

    assert_equal [1, nil], [result.code, body]
    assert_includes result.err, "the spec file cannot be read"
  end

  %w[done abandoned].each do |status|
    define_method(:"test_a_#{status}_intent_refuses_a_new_spec_and_offers_next") do
      open_intent(status:)

      result = call("1", "--from", draft)

      assert_equal [3, nil], [result.code, body]
      assert_includes result.err, "intent 1 is #{status}; a closed intent keeps its spec"
      assert_match(/^next: plastic next/, result.out)
    end
  end

  def test_the_spec_without_from_writes_nothing
    open_intent

    result = call("1")

    assert_equal [0, nil], [result.code, body]
    refute_includes result.out, "spec: written"
  end
end

class IntentSpecFromEncodingTest < Plastic::TestCase
  def test_a_spec_file_that_is_not_utf_8_fails_and_writes_nothing
    open_intent
    path = File.join(@home, "draft.md")
    File.binwrite(path, "# Spec\n\xFF\n")

    result = plastic("intent", "spec", "1", "--from", path, table: Plastic::CLI::TABLE)

    assert_equal [1, nil], [result.code, retrieval.fetch("1", "spec.md")]
    assert_includes result.err, "the spec file #{path} is not UTF-8 text"
  end
end
