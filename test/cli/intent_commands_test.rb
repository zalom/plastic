# frozen_string_literal: true

require_relative "../test_helper"
require "stringio"
require "tmpdir"
require_relative "../lib/cli_fixture"
require_relative "../../scripts/lib/cli"
require_relative "../../scripts/lib/cli/commands/intent_command"

class CliIntentCommandsTest < Minitest::Test
  class Bare < Plastic::CLI::Commands::IntentCommand
    USAGE_LINE = "plastic bare ID"
    SCRIPT = "report-screen"
    AFTER = "plastic status"
    BECAUSE = "a stand-in for coverage"
  end

  def setup
    @dir = Dir.mktmpdir("plastic-cli-intent")
    @fixture = CliFixture.new(@dir).global_store(active: [["372", "Skills to commands"]])
    @calls = []
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def intent_dir
    @fixture.intent_dir("global", "372")
  end

  def store
    File.join(@fixture.plastic_home, "store")
  end

  # Runs one intent command class directly, with a runner double that never
  # spawns a real script - the same seam test/cli/installer_verbs_test.rb uses.
  def command(verb, *argv, status: 0, directory: "/nowhere")
    file, const, = Plastic::CLI::TABLE.fetch(verb)
    require File.expand_path("../../scripts/lib/cli/#{file}", __dir__)
    runner = lambda do |path, arguments|
      @calls << [path, arguments]
      status
    end
    Plastic::CLI::Commands.const_get(const).call(argv, directory: directory, runner: runner, **@fixture.streams)
  end

  # Runs the real dispatcher, for the cases that turn on matching, not on the
  # runner seam: an unknown subcommand, an unknown flag, an unknown id, and
  # the bare listing. None of these ever reaches `legacy.run`.
  def run_cli(*argv)
    Plastic::CLI.call(argv, directory: "/nowhere", **@fixture.streams)
  end

  def script(name)
    File.expand_path("../../scripts/#{name}", __dir__)
  end

  # --- intent show -----------------------------------------------------------

  def test_show_runs_report_screen_state
    command("intent show", "372")

    assert_equal [script("report-screen")], @calls.map(&:first)
    assert_equal [["state", intent_dir]], @calls.map(&:last)
  end

  def test_show_names_the_id_in_its_next_step
    command("intent show", "372")

    assert_includes @fixture.printed, "next: plastic intent spec 372"
  end

  def test_a_failing_script_exits_one
    assert_equal 1, command("intent show", "372", status: 7)
  end

  def test_a_failing_script_names_the_script_and_its_status
    command("intent show", "372", status: 7)

    assert_includes @fixture.warned, "report-screen exited 7"
  end

  # --- intent spec -------------------------------------------------------------

  def test_spec_runs_report_screen_state
    command("intent spec", "372")

    assert_equal [["state", intent_dir]], @calls.map(&:last)
  end

  def test_spec_prints_the_speccing_rules
    command("intent spec", "372")

    assert_includes @fixture.printed, "one question per message"
    assert_includes @fixture.printed, "record every ruling the instant it lands"
  end

  # --- intent rule -------------------------------------------------------------

  def test_rule_runs_insight_append
    command("intent rule", "372", "ship the thin slice first")

    assert_equal [script("insight-append")], @calls.map(&:first)
    assert_equal [[intent_dir, "ship the thin slice first", "--stage", "Why", "--author", "human"]],
      @calls.map(&:last)
  end

  def test_rule_without_text_exits_two
    assert_equal 2, command("intent rule", "372")
  end

  # --- intent note -------------------------------------------------------------

  def test_note_runs_savepoint_note_with_the_default_kind
    command("intent note", "372", "checkpoint before the risky part")

    assert_equal [script("savepoint-note")], @calls.map(&:first)
    assert_equal [[intent_dir, "--kind", "Report", "--text", "checkpoint before the risky part"]],
      @calls.map(&:last)
  end

  def test_note_kind_is_passed_through
    command("intent note", "372", "landed", "--kind", "Commit")

    assert_equal [[intent_dir, "--kind", "Commit", "--text", "landed"]], @calls.map(&:last)
  end

  def test_note_without_text_exits_two
    assert_equal 2, command("intent note", "372")
  end

  # --- intent step -------------------------------------------------------------

  def test_end_rejects_conflicting_dispositions_before_any_script_runs
    status = command("intent end", "372", "--delivered", "--abandoned", "--summary", "Ambiguous")

    assert_equal 2, status
    assert_empty @calls
  end

  def test_step_runs_runner_step
    File.write(File.join(intent_dir, "graph.md"), "# graph\n")
    require_relative "../../scripts/lib/arm"
    Lock.acquire(intent_dir, session: Arm.derive_key(store, "372"))
    command("intent step", "372")

    assert_equal [script("runner")], @calls.map(&:first)
    assert_equal [["step", intent_dir]], @calls.map(&:last)
  end

  def test_step_with_no_graph_prints_the_non_graph_procedure
    command("intent step", "372")

    assert_empty @calls
    assert_includes @fixture.printed, "next: plastic intent spec 372"
  end

  def test_step_forwards_multiple_returns_and_harness_options
    File.write(File.join(intent_dir, "graph.md"), "# graph\n")
    require_relative "../../scripts/lib/arm"
    Lock.acquire(intent_dir, session: Arm.derive_key(store, "372"))
    command("intent step", "372", "--return", "n1=/tmp/one.yml", "--return", "n2=/tmp/two.yml",
      "--harness", "codex-cli", "--allow-core-drift")

    assert_equal ["step", intent_dir, "--return", "n1=/tmp/one.yml", "--return", "n2=/tmp/two.yml",
      "--harness", "codex-cli", "--allow-core-drift"], @calls.last.last
  end

  def test_step_with_a_graph_does_not_print_the_non_graph_procedure
    File.write(File.join(intent_dir, "graph.md"), "# graph\n")
    command("intent step", "372")

    refute_includes @fixture.printed, "dispatch ONE plastic-executor subagent"
  end

  def test_graph_return_requires_ownership
    File.write(File.join(intent_dir, "graph.md"), "# graph\n")

    status = run_cli("intent", "step", "372", "--return", "n1=/tmp/return.yml")

    assert_equal 3, status
    assert_empty @calls
    refute_path_exists File.join(intent_dir, "delivery.lock")
  end

  # --- intent answer -----------------------------------------------------------

  def test_answer_runs_runner_answer
    command("intent answer", "372", "--node", "n3", "--decision", "go with plan B")

    assert_equal [script("runner")], @calls.map(&:first)
    assert_equal [["answer", intent_dir, "--node", "n3", "--answer", "go with plan B"]], @calls.map(&:last)
  end

  def test_answer_without_node_exits_two
    assert_equal 2, command("intent answer", "372", "--decision", "text")
  end

  def test_answer_without_decision_exits_two
    assert_equal 2, command("intent answer", "372", "--node", "n3")
  end

  # --- intent verify -----------------------------------------------------------

  def test_verify_runs_verify_intent
    command("intent verify", "372")

    assert_equal [script("verify-intent")], @calls.map(&:first)
    assert_equal [["--store", store, "--id", "372"]], @calls.map(&:last)
  end

  # --- intent end --------------------------------------------------------------

  def test_end_runs_end_intent
    command("intent end", "372", "--delivered", "--summary", "shipped the thin slice")

    assert_equal [script("end-intent")], @calls.map(&:first)
    assert_equal [["--store", store, "--id", "372", "--disposition", "delivered",
      "--outcome-summary", "shipped the thin slice"]], @calls.map(&:last)
  end

  def test_end_passes_through_the_note_and_dry_run
    command("intent end", "372", "--abandoned", "--summary", "scope moved", "--note", "see 375",
      "--dry-run")

    assert_equal [["--store", store, "--id", "372", "--disposition", "abandoned",
      "--outcome-summary", "scope moved", "--index-note", "see 375", "--dry-run"]], @calls.map(&:last)
  end

  def test_end_without_a_disposition_exits_two
    assert_equal 2, command("intent end", "372", "--summary", "text")
  end

  def test_end_without_a_summary_exits_two
    assert_equal 2, command("intent end", "372", "--delivered")
  end

  def test_end_without_a_summary_prints_the_three_summary_lines
    command("intent end", "372", "--delivered")

    assert_includes @fixture.warned, "reader deciding whether to merge, release, or accept"
    assert_includes @fixture.warned, "delivered: what shipped, impact and risk first"
    assert_includes @fixture.warned, "abandoned: why, and the trail"
  end

  def test_end_without_a_summary_never_runs_the_script
    command("intent end", "372", "--delivered")

    assert_empty @calls
  end

  def test_end_exit_four_becomes_a_refusal
    assert_equal 3,
      command("intent end", "372", "--delivered", "--summary", "text", status: 4)
  end

  def test_end_a_refusal_names_the_owner
    command("intent end", "372", "--delivered", "--summary", "text", status: 4)

    assert_includes @fixture.warned, "needs the owner"
  end

  def test_end_a_plain_failing_status_exits_one
    assert_equal 1, command("intent end", "372", "--delivered", "--summary", "text", status: 2)
  end

  # --- intent new ----------------------------------------------------------------

  def new_fresh_idea
    FileUtils.mkdir_p(File.join(store, "373--fresh-idea"))
    command("intent new", "a fresh idea", "--slug", "fresh-idea")
  end

  def test_new_runs_new_intent
    new_fresh_idea

    assert_equal [script("new-intent")], @calls.map(&:first)
    assert_equal ["--store", store, "--intent", "a fresh idea", "--slug", "fresh-idea"], @calls[0].last
  end

  def test_new_files_the_intent_under_active
    new_fresh_idea

    index = File.read(File.join(@fixture.plastic_home, "INDEX.md"), encoding: "UTF-8")

    assert_includes index, "## Active\n- [373 \u2014 a fresh idea](store/373--fresh-idea/373--fresh-idea.md)\n"
  end

  def test_new_names_the_new_id_in_its_next_step
    new_fresh_idea

    assert_includes @fixture.printed, "next: plastic intent spec 373"
  end

  def test_new_with_no_directory_afterwards_exits_one
    assert_equal 1, command("intent new", "a fresh idea", "--slug", "fresh-idea")
  end

  def test_new_passes_through_parent_sources_and_tags
    command("intent new", "a fresh idea", "--slug", "fresh-idea", "--parent", "372",
      "--sources", "41,363", "--tags", "cli")

    assert_equal ["--store", store, "--intent", "a fresh idea", "--slug", "fresh-idea",
      "--parent", "372", "--sources", "41,363", "--tags", "cli"], @calls[0].last
  end

  def test_new_without_a_line_exits_two
    assert_equal 2, command("intent new", "--slug", "fresh-idea")
  end

  def test_new_without_a_slug_takes_it_from_the_first_five_words
    command("intent new", "Move the Plastic skills to commands, family by family")

    assert_equal "move-the-plastic-skills-to", @calls[0].last.last
  end

  def test_new_with_a_failing_new_intent_exits_one
    assert_equal 1, command("intent new", "a fresh idea", "--slug", "fresh-idea", status: 9)
  end

  # --- the base class: an id that names no intent -------------------------------

  def test_an_unknown_intent_id_exits_one
    assert_equal 1, run_cli("intent", "show", "999")
  end

  def test_an_unknown_intent_id_names_plastic_status
    run_cli("intent", "show", "999")

    assert_includes @fixture.warned, "plastic status lists the ones that exist"
  end

  def test_an_unknown_intent_id_never_runs_a_script
    run_cli("intent", "show", "999")

    assert_empty @calls
  end

  # --- an unknown flag -----------------------------------------------------------

  def test_an_unknown_flag_exits_two
    assert_equal 2, run_cli("intent", "show", "372", "--bogus")
  end

  def test_an_unknown_flag_prints_the_usage_line
    require_relative "../../scripts/lib/cli/commands/intent_show"
    run_cli("intent", "show", "372", "--bogus")

    assert_includes @fixture.warned, Plastic::CLI::Commands::IntentShow::USAGE_LINE
  end

  # --- plastic intent, alone or with an unknown word -----------------------------

  def test_bare_intent_lists_the_subcommands
    assert_equal 0, run_cli("intent")

    assert_includes @fixture.printed, "intent show"
    assert_includes @fixture.printed, "intent verify"
  end

  def test_an_unknown_subcommand_exits_two
    assert_equal 2, run_cli("intent", "bogus")
  end

  def test_a_subclass_that_defines_no_script_arguments_says_so_by_name
    error = assert_raises(NoMethodError) do
      CliIntentCommandsTest::Bare.new(["372"], out: @fixture.out, err: @fixture.err, env: @fixture.env,
        home: @fixture.home, directory: "/nowhere").call
    end

    assert_equal "#{CliIntentCommandsTest::Bare} must define script_arguments", error.message
  end

  def test_an_unknown_subcommand_lists_the_subcommands
    run_cli("intent", "bogus")

    Plastic::CLI::TABLE.keys.select { |name| name.start_with?("intent ") }.each do |name|
      assert_includes @fixture.warned, name
    end
  end

  def test_an_unknown_project_is_rejected_before_a_mutation
    status = command("intent rule", "372", "a ruling", "--project", "missing")

    assert_equal 2, status
    assert_empty @calls
  end
end
