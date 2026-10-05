# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../scripts/lib/plastic/commands/graph_resume"
require_relative "../../../scripts/lib/plastic/commands/next"
require_relative "../../../scripts/lib/plastic/commands/auto_start"
require_relative "../../../scripts/lib/plastic/commands/node_add"
require_relative "../../../scripts/lib/plastic/commands/node_claim"
require_relative "../../../scripts/lib/plastic/commands/node_done"
require_relative "../../../scripts/lib/plastic/commands/node_fail"
require_relative "../../../scripts/lib/plastic/commands/node_park"
require_relative "../../../scripts/lib/plastic/commands/sync_up"

class GraphResumeTest < Plastic::TestCase
  CLEAR_SPEC = "# Spec\n\n## Done criteria\n- ships\n\n## Open Questions\n- none\n"

  def call(*args) = plastic("graph", "resume", *args, table: Plastic::CLI::TABLE)

  def lines(result) = result.out.lines(chomp: true).map { |line| line.squeeze(" ") }

  def next_line(result) = lines(result).find { |line| line.start_with?("next:") }

  def register(*slugs)
    entries = slugs.map { |slug| "  #{slug}:\n    path: #{Dir.mktmpdir}\n" }.join
    File.write(File.join(@plastic_home, "projects.yml"), "projects:\n#{entries}")
  end

  def store_folder(slug) = Plastic::Graph::Knowledge::StoreFolder.new(File.join(@plastic_home, "stores", slug))

  def store_intent(slug, title)
    work = Plastic::Graph.open(home: @plastic_home, store: slug).work
    intent = work.write_intent(title:)
    work.print_intent(intent.intent_id)
    intent
  end

  def clear_spec(slug, intent)
    store_folder(slug).write("#{intent.dir}/spec.md", CLEAR_SPEC)
    plastic("sync", "up", "--project", slug, table: Plastic::CLI::TABLE)
  end

  def ready_intent(title = "Alpha")
    intent = open_intent(title)
    write("#{intent.dir}/spec.md", CLEAR_SPEC)
    plastic("sync", "up", table: Plastic::CLI::TABLE)
    plastic("auto", "start", intent.intent_id, env: { "PLASTIC_SESSION" => "s-1" }, table: Plastic::CLI::TABLE)
    intent
  end

  def add_node(intent, title) = plastic("node", "add", intent.intent_id, title, "--criterion", "done", table: Plastic::CLI::TABLE)

  def node(verb, intent, node_id, *rest) = plastic("node", verb, intent.intent_id, node_id, *rest, table: Plastic::CLI::TABLE)

  def intent_with_nodes_in_each_state
    intent = ready_intent
    %w[a b c d].each { |title| add_node(intent, title) }
    %w[n1 n2 n3 n4].each { |node_id| node("claim", intent, node_id) }
    node("done", intent, "n1", "--judge", "owner", "--findings", "ok")
    node("fail", intent, "n3", "--reason", "broke")
    node("park", intent, "n4", "--question", "which way")
    intent
  end

  def test_one_store_names_the_intent_in_play
    intent_with_nodes_in_each_state

    result = call

    assert_equal 0, result.code
    assert_equal "", result.err
    assert_includes lines(result), "store: global"
    assert_includes lines(result), "in play: 1 Alpha (active)"
  end

  def test_a_done_node_prints_as_a_done_line
    intent_with_nodes_in_each_state

    assert_includes lines(call), "done: n1 a"
  end

  def test_claimed_failed_and_parked_nodes_print_as_in_progress_lines
    intent_with_nodes_in_each_state

    assert_includes lines(call), "in progress: n2 claimed b"
    assert_includes lines(call), "in progress: n3 failed c"
    assert_includes lines(call), "in progress: n4 parked d"
  end

  def test_a_done_node_is_not_listed_as_in_progress
    intent_with_nodes_in_each_state

    refute_includes lines(call), "in progress: n1 done a"
  end

  def test_the_last_savepoint_lines_of_the_intent_in_play_print
    intent_with_nodes_in_each_state

    assert lines(call).any? { |line| line.start_with?("savepoint:") && line.end_with?("Opened: Alpha") }
  end

  def test_no_more_than_five_savepoint_lines_print
    intent_with_nodes_in_each_state

    assert_operator lines(call).count { |line| line.start_with?("savepoint:") }, :<=, 5
  end

  def test_a_ready_node_gives_the_claim_command_plastic_next_gives
    intent = ready_intent
    add_node(intent, "a")

    assert_equal "next: plastic node claim 1 n1 --project global", next_line(call)
    assert_equal next_line(plastic("next", table: Plastic::CLI::TABLE)), next_line(call)
  end

  def test_an_intent_with_no_nodes_hands_planning_to_the_agent
    ready_intent

    result = call

    assert_includes lines(result), "then: Read the intent's goal and done criteria. Add work with plastic node add 1 TITLE --criterion TEXT, " \
      "then add dependencies with plastic edge add. Use plastic graph ready 1 after the plan is recorded."
    refute_includes result.out, "then: (because"
  end

  def test_several_open_intents_and_no_lock_pick_none
    open_intent("Alpha")
    open_intent("Beta")

    result = call

    assert_includes lines(result), "in play: none alone"
    assert_includes lines(result), "open: 1 Alpha (open)"
    assert_includes lines(result), "open: 2 Beta (open)"
  end

  def test_a_store_with_nothing_open_has_no_intent_in_play
    result = call

    assert_includes lines(result), "in play: none"
    assert_includes lines(result), "then: none (because nothing is open)"
  end

  def test_no_store_with_work_sends_the_agent_to_plastic_status
    result = call

    assert_equal "next: plastic status", next_line(result)
  end

  def test_two_stores_print_in_the_order_named
    register("b")
    store_intent("b", "Beta")
    open_intent("Alpha")

    result = call("--stores", "b,global")

    assert_equal %w[store:\ b store:\ global], lines(result).grep(/\Astore:/)
  end

  def test_the_next_line_names_the_first_store_with_work
    register("b")
    clear_spec("b", store_intent("b", "Beta"))
    open_intent("Alpha")

    result = call("--stores", "b,global")

    assert_equal "next: plastic auto start 1 --project b", next_line(result)
    assert_includes lines(result).find { |line| line.start_with?("because:") }, "store b"
  end

  def test_the_next_line_skips_a_store_with_nothing_open
    register("b")
    clear_spec("b", store_intent("b", "Beta"))

    result = call("--stores", "global,b")

    assert_equal "next: plastic auto start 1 --project b", next_line(result)
  end

  def test_each_then_line_holds_a_stores_own_next_command
    register("b")
    clear_spec("b", store_intent("b", "Beta"))

    result = call("--stores", "global,b")

    assert_includes lines(result), "then: none (because nothing is open)"
    assert_includes lines(result), "then: plastic auto start 1 (because intent 1 is open)"
  end

  def test_a_name_that_is_no_project_exits_2_and_lists_the_projects
    register("b")

    result = call("--stores", "nope")

    assert_equal [2, ""], [result.code, result.out]
    assert_includes result.err, "no registered project named \"nope\"; the projects are b"
  end

  def test_stores_with_project_exits_2
    register("b")

    result = call("--stores", "b", "--project", "b")

    assert_equal [2, ""], [result.code, result.out]
    assert_includes result.err, "--stores"
  end

  def test_a_store_named_twice_prints_once
    register("b")
    store_intent("b", "Beta")

    result = call("--stores", "b,b")

    assert_equal ["store: b"], lines(result).grep(/\Astore:/)
  end

  def test_rows_missing_and_files_present_say_how_many_intent_folders_the_files_hold
    register("c")
    FileUtils.mkdir_p(File.join(@plastic_home, "stores", "c", "store", "1--first"))
    FileUtils.mkdir_p(File.join(@plastic_home, "stores", "c", "store", "2--second"))

    result = call("--stores", "c")

    assert_equal 0, result.code
    assert_includes lines(result), "rows: none; the files hold 2 intent folders"
  end

  def test_rows_missing_with_no_index_say_no_command_rebuilds_them
    register("c")
    FileUtils.mkdir_p(File.join(@plastic_home, "stores", "c", "store", "1--first"))

    assert_includes lines(call("--stores", "c")), "then: no command rebuilds these rows today"
  end

  def test_sync_up_refuses_an_intent_folder_with_no_row_and_no_index
    register("c")
    store_folder("c").write("store/1--first/spec.md", CLEAR_SPEC)

    result = plastic("sync", "up", "--project", "c", table: Plastic::CLI::TABLE)

    refute_equal 0, result.code
    assert_empty Plastic::Graph.open(home: @plastic_home, store: "c").retrieval.intents
  end

  def test_sync_up_stops_at_the_index_of_a_folder_with_no_rows_for_the_owner_to_settle
    register("c")
    store_intent("src", "First")
    copy_intent_files("src", "c")

    result = plastic("sync", "up", "--project", "c", table: Plastic::CLI::TABLE)

    assert_equal 3, result.code
    assert_empty Plastic::Graph.open(home: @plastic_home, store: "c").retrieval.intents
  end

  def test_sync_up_with_overwrite_rebuilds_the_rows_of_a_folder_that_holds_its_index
    register("c")
    intent = store_intent("src", "First")
    copy_intent_files("src", "c")

    result = plastic("sync", "up", "--project", "c", "--overwrite", table: Plastic::CLI::TABLE)

    assert_equal 0, result.code
    assert_equal [intent.intent_id], Plastic::Graph.open(home: @plastic_home, store: "c").retrieval.intents.map(&:intent_id)
  end

  def test_rows_missing_with_an_index_name_the_rebuild_and_leave_it_to_the_owner
    register("c")
    store_intent("src", "First")
    copy_intent_files("src", "c")

    assert_includes lines(call("--stores", "c")),
      "then: plastic sync up --project c --overwrite rebuilds them from the files; the owner settles that step"
  end

  def test_a_store_with_rows_missing_offers_no_next_command
    register("c")
    store_intent("src", "First")
    copy_intent_files("src", "c")

    assert_equal "next: plastic status", next_line(call("--stores", "c"))
  end

  def copy_intent_files(from, to)
    source = store_folder(from)
    target = store_folder(to)
    Dir.glob("store/**/*", base: source.root).select { |rel| source.exist?(rel) }.each { |rel| target.write(rel, source.read(rel)) }
  end

  def test_a_resume_changes_no_database_and_no_file
    intent_with_nodes_in_each_state
    before = snapshot(store_root)

    call

    assert_equal before, snapshot(store_root)
  end
end
