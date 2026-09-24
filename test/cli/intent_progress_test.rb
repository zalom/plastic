# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../lib/cli_fixture"
require_relative "../../scripts/lib/cli"
require_relative "../../scripts/lib/cli/intent_progress"
require_relative "../../scripts/lib/cli/commands/intent_step"
require "tmpdir"
require "json"

class CliIntentProgressTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("plastic-progress")
    @fixture = CliFixture.new(@dir).global_store(active: [["1", "Example"]])
    @intent = @fixture.intent_dir("global", "1")
    @scope = Plastic::CLI::Scope.new(env: @fixture.env, home: @fixture.home, directory: @dir)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def write(name, body)
    File.write(File.join(@intent, "#{name}.md"), body)
  end

  def prepare
    write("spec", "# Specification")
    write("plan", "# Plan")
    write("checklist", "- [ ] Deliver example\n")
  end

  def decision
    Plastic::CLI::IntentProgress.new(@scope, "1").decision
  end

  def test_terminal_work_has_no_next_action
    @fixture.global_store(completed: [["1", "Example"]])

    assert_equal ["none", "the intent is completed"], decision
  end

  def test_placeholder_spec_requires_preparation
    write("spec", "<!-- plastic:placeholder -->\n# Specification")

    assert_equal "plastic intent spec 1", decision.first
  end

  def test_blank_spec_requires_preparation
    write("spec", " ")

    assert_equal "plastic intent spec 1", decision.first
  end

  def test_missing_plan_requires_preparation
    write("spec", "# Specification")
    FileUtils.rm_f(File.join(@intent, "plan.md"))

    assert_includes decision.last, "write plan.md"
  end

  def test_missing_checklist_requires_preparation
    write("spec", "# Specification")

    assert_includes decision.last, "write plan.md and checklist.md"
  end

  def test_graph_selects_step
    prepare
    write("graph", "# Graph")

    assert_equal ["plastic intent step 1", "the graph is ready for its next step"], decision
  end

  def test_empty_checklist_requires_concrete_items
    prepare
    write("checklist", "# Checklist")

    assert_equal ["plastic intent spec 1", "the checklist needs concrete work items"], decision
  end

  def test_finished_checklist_selects_verification
    prepare
    write("checklist", "- [x] Deliver example\n")

    assert_equal ["plastic intent verify 1", "all checklist items are complete"], decision
  end

  def test_unfinished_checklist_selects_step
    prepare

    assert_equal ["plastic intent step 1", "the checklist has unfinished work"], decision
  end

  def step
    Plastic::CLI::Commands::IntentStep.call(["1", "--json"], directory: @dir, **@fixture.streams)
  end

  def test_direct_step_prints_work_without_dispatch
    prepare

    assert_equal 0, step
    assert_equal "Deliver example", JSON.parse(@fixture.printed).dig("result", "work")
    assert_equal "none", JSON.parse(@fixture.printed).fetch("next")
  end

  def test_graph_with_no_lock_names_take
    prepare
    write("graph", "# Graph")

    assert_equal 0, step
    assert_equal "plastic auto start 1 --project global", JSON.parse(@fixture.printed).fetch("next")
  end

  def test_foreign_lock_refuses_with_public_inspection_command
    prepare
    write("graph", "# Graph")
    Lock.acquire(@intent, session: "another-owner")

    assert_equal 3, step
    assert_includes @fixture.warned, "plastic auto lock status 1 --project global"
    assert_equal "refused", JSON.parse(@fixture.printed).dig("result", "error", "kind")
  end

  def test_terminal_graph_does_not_acquire_or_dispatch
    @fixture.global_store(completed: [["1", "Example"]])
    write("graph", "# Graph")

    assert_equal 0, step
    assert_equal "none", JSON.parse(@fixture.printed).fetch("next")
  end

  def test_graph_does_not_require_legacy_specification_files
    write("graph", "# Graph")

    assert_equal "plastic intent step 1", decision.first
  end
end
